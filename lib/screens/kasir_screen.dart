import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'setup_screen.dart';

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  String _namaKasir = '';
  String _namaCabang = '';
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  // Data Produk Dummy (Sementara, nanti akan diambil dari Spreadsheet)
  final List<Map<String, dynamic>> _produkList = [
    {'id': 'P001', 'nama': 'Kopi Susu', 'harga': 20000},
    {'id': 'P002', 'nama': 'Roti Bakar', 'harga': 15000},
    {'id': 'P003', 'nama': 'Air Mineral', 'harga': 5000},
    {'id': 'P004', 'nama': 'Nasi Goreng', 'harga': 25000},
  ];

  // Data Keranjang Belanja
  final List<Map<String, dynamic>> _keranjang = [];

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
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const SetupScreen()),
    );
  }

  // Fungsi Tambah Produk ke Keranjang
  void _tambahKeKeranjang(Map<String, dynamic> produk) {
    setState(() {
      int index = _keranjang.indexWhere((item) => item['id'] == produk['id']);
      if (index != -1) {
        _keranjang[index]['qty']++;
      } else {
        _keranjang.add({
          'id': produk['id'],
          'nama': produk['nama'],
          'harga': produk['harga'],
          'qty': 1,
        });
      }
    });
  }

  // Fungsi Hitung Total
  int get _totalBelanja {
    int total = 0;
    for (var item in _keranjang) {
      total += (item['harga'] as int) * (item['qty'] as int);
    }
    return total;
  }

  // Fungsi Hapus Item dari Keranjang
  void _hapusItem(int index) {
    setState(() {
      _keranjang.removeAt(index);
    });
  }

  // Fungsi Proses Pembayaran
  void _prosesBayar() {
    if (_keranjang.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keranjang masih kosong!')),
      );
      return;
    }
    
    // Nanti di sini kita akan menambahkan fungsi simpan ke Apps Script & Cetak Printer
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pembayaran Berhasil'),
          content: Text('Total: ${_currencyFormat.format(_totalBelanja)}\n\n(Di tahap selanjutnya, data akan dikirim ke Google Sheets & Printer)'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _keranjang.clear(); // Kosongkan keranjang setelah bayar
                });
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Reset Pengaturan',
          ),
        ],
      ),
      body: Row(
        children: [
          // BAGIAN KIRI: Daftar Produk
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
          
          // BAGIAN KANAN: Keranjang Belanja
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
                                onPressed: () => _hapusItem(index),
                              ),
                            );
                          },
                        ),
                ),
                
                // BAGIAN TOTAL & TOMBOL BAYAR
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                            _currencyFormat.format(_totalBelanja),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _prosesBayar,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                          child: const Text('BAYAR SEKARANG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
