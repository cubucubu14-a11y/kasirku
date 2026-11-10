import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/printer_service.dart';
import '../services/database_helper.dart';
import 'setup_screen.dart';

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  String _namaKasir = '';
  String _namaCabang = '';
  String _urlAppScript = '';
  int _pendingCount = 0;
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  final List<Map<String, dynamic>> _produkList = [
    {'id': 'P001', 'nama': 'Kopi Susu', 'harga': 20000},
    {'id': 'P002', 'nama': 'Roti Bakar', 'harga': 15000},
    {'id': 'P003', 'nama': 'Air Mineral', 'harga': 5000},
    {'id': 'P004', 'nama': 'Nasi Goreng', 'harga': 25000},
  ];

  final List<Map<String, dynamic>> _keranjang = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _namaKasir = prefs.getString('nama_kasir') ?? '';
      _namaCabang = prefs.getString('nama_cabang') ?? '';
      _urlAppScript = prefs.getString('url_appscript') ?? '';
    });
    _updatePendingCount();
  }

  Future<void> _updatePendingCount() async {
    final antrean = await DatabaseHelper.instance.getAntrean();
    setState(() {
      _pendingCount = antrean.length;
    });
  }

  Future<void> _sinkronisasiData() async {
    if (_urlAppScript.isEmpty) return;
    
    setState(() => _isLoading = true);
    final antrean = await DatabaseHelper.instance.getAntrean();
    int berhasil = 0;

    for (var item in antrean) {
      final data = jsonDecode(item['data_json']);
      bool sukses = await ApiService.kirimTransaksi(
        _urlAppScript,
        data['nama_cabang'],
        data['nama_kasir'],
        List<Map<String, dynamic>>.from(data['items']),
      );

      if (sukses) {
        await DatabaseHelper.instance.hapusAntrean(item['id']);
        berhasil++;
      }
    }

    await _updatePendingCount();
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sinkronisasi selesai. $berhasil data terkirim ke Spreadsheet.')),
      );
    }
  }

  void _tambahKeKeranjang(Map<String, dynamic> produk) {
    setState(() {
      int index = _keranjang.indexWhere((item) => item['id'] == produk['id']);
      if (index != -1) {
        _keranjang[index]['qty']++;
      } else {
        _keranjang.add({'id': produk['id'], 'nama': produk['nama'], 'harga': produk['harga'], 'qty': 1});
      }
    });
  }

  int get _totalBelanja {
    int total = 0;
    for (var item in _keranjang) {
      total += (item['harga'] as int) * (item['qty'] as int);
    }
    return total;
  }

  Future<void> _prosesBayar() async {
    if (_keranjang.isEmpty) return;
    setState(() => _isLoading = true);

    final dataTransaksi = {
      "nama_cabang": _namaCabang,
      "nama_kasir": _namaKasir,
      "items": _keranjang,
    };

    await DatabaseHelper.instance.simpanAntrean(dataTransaksi);
    await _updatePendingCount();

    // Panggil fungsi printer (simulasi)
    await PrinterService.cetakStruk(_namaCabang, _namaKasir, _keranjang, _totalBelanja);

    await _sinkronisasiData();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transaksi Disimpan'),
        content: Text('Total: ${_currencyFormat.format(_totalBelanja)}\nData tersimpan di HP. Struk berhasil dicetak (simulasi).'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _keranjang.clear());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kasir: $_namaCabang', style: const TextStyle(fontSize: 16)),
            Text('Petugas: $_namaKasir', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: _isLoading ? null : _sinkronisasiData,
                tooltip: 'Sinkronisasi Data',
              ),
              if (_pendingCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                )
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SetupScreen()));
            },
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.grey[100],
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _produkList.length,
                itemBuilder: (context, index) {
                  final produk = _produkList[index];
                  return Card(
                    child: ListTile(
                      title: Text(produk['nama'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(_currencyFormat.format(produk['harga'])),
                      trailing: const Icon(Icons.add_circle, color: Colors.blue, size: 30),
                      onTap: () => _tambahKeKeranjang(produk),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(
                  child: _keranjang.isEmpty
                      ? const Center(child: Text('Belum ada item dipilih', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _keranjang.length,
                          itemBuilder: (context, index) {
                            final item = _keranjang[index];
                            return ListTile(
                              leading: CircleAvatar(child: Text(item['qty'].toString())),
                              title: Text(item['nama']),
                              subtitle: Text(_currencyFormat.format(item['harga'] * item['qty'])),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => setState(() => _keranjang.removeAt(index)),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))]),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(_currencyFormat.format(_totalBelanja), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _prosesBayar,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                          child: _isLoading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('BAYAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
