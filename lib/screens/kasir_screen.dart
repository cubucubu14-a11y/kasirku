import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../services/printer_service.dart';

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  String _namaKasir = '';
  String _namaCabang = '';
  String _urlAppScript = '';
  List<Map<String, dynamic>> _produkList = [];
  final List<Map<String, dynamic>> _keranjang = [];
  String _kategoriAktif = 'Semua';
  BluetoothDevice? _selectedPrinter;
  bool _isLoading = false;

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final produk = await DatabaseHelper.instance.getProduk();
    setState(() {
      _namaKasir = prefs.getString('nama_kasir') ?? '';
      _namaCabang = prefs.getString('nama_cabang') ?? '';
      _urlAppScript = prefs.getString('url_appscript') ?? '';
      _produkList = produk;
    });
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

  void _kurangiKeranjang(int index) {
    setState(() {
      if (_keranjang[index]['qty'] > 1) {
        _keranjang[index]['qty']--;
      } else {
        _keranjang.removeAt(index);
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

  Future<void> _pilihPrinter() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Printer Bluetooth'),
        content: FutureBuilder<List<BluetoothDevice>>(
          future: PrinterService.getPrinters(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const CircularProgressIndicator();
            if (snapshot.data!.isEmpty) return const Text('Tidak ada printer. Pairing dulu di setting HP.');
            return SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final printer = snapshot.data![index];
                  return ListTile(
                    title: Text(printer.name ?? 'Printer'),
                    trailing: _selectedPrinter?.address == printer.address ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: () {
                      setState(() => _selectedPrinter = printer);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _bukaKeranjang() {
    if (_keranjang.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  const Text('Keranjang Belanja', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _keranjang.length,
                      itemBuilder: (context, index) {
                        final item = _keranjang[index];
                        return Card(
                          elevation: 0,
                          color: Colors.grey[100],
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white, child: Text(item['qty'].toString())),
                            title: Text(item['nama']),
                            subtitle: Text(_currencyFormat.format(item['harga'] * item['qty'])),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.remove_circle, color: Colors.orange), onPressed: () {
                                  setModalState(() => _kurangiKeranjang(index));
                                  setState(() {});
                                }),
                                IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () {
                                  setModalState(() => _tambahKeKeranjang(item));
                                  setState(() {});
                                }),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(_currencyFormat.format(_totalBelanja), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showPembayaranDialog();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
                      child: const Text('PROSES BAYAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPembayaranDialog() {
    String metode = 'Tunai';
    final bayarC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            int bayar = int.tryParse(bayarC.text) ?? 0;
            int kembali = bayar - _totalBelanja;
            if (kembali < 0) kembali = 0;

            return AlertDialog(
              title: const Text('Pembayaran'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total: ${_currencyFormat.format(_totalBelanja)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ChoiceChip(label: const Text('Tunai'), selected: metode == 'Tunai', onSelected: (v) => setDialogState(() => metode = 'Tunai')),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Kris/QRIS'), selected: metode == 'Kris', onSelected: (v) => setDialogState(() => metode = 'Kris')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (metode == 'Tunai') ...[
                    TextField(
                      controller: bayarC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Uang Diterima', border: OutlineInputBorder()),
                      onChanged: (v) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text('Kembalian: ${_currencyFormat.format(kembali)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ] else ...[
                    const Text('Pembayaran via Kris/QRIS diasumsikan Uang Pas.', style: TextStyle(fontStyle: FontStyle.italic)),
                  ]
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: _isLoading ? null : () async {
                    int uangBayar = metode == 'Tunai' ? (int.tryParse(bayarC.text) ?? 0) : _totalBelanja;
                    if (metode == 'Tunai' && uangBayar < _totalBelanja) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uang kurang!')));
                      return;
                    }
                    Navigator.pop(context);
                    await _prosesBayar(metode, uangBayar, kembali);
                  },
                  child: const Text('SELESAIKAN'),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _prosesBayar(String metode, int bayar, int kembali) async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final idTrx = "TRX-${now.millisecondsSinceEpoch}";

    await DatabaseHelper.instance.simpanTransaksi({
      'id_transaksi': idTrx,
      'tanggal': DateFormat('yyyy-MM-dd').format(now),
      'waktu': DateFormat('HH:mm:ss').format(now),
      'total': _totalBelanja,
      'items_json': jsonEncode(_keranjang),
      'status_sync': 0,
    });

    if (_urlAppScript.isNotEmpty) {
      bool sukses = await ApiService.kirimTransaksi(_urlAppScript, _namaCabang, _namaKasir, _keranjang, metode);
      if (sukses) await DatabaseHelper.instance.updateStatusSync(idTrx);
    }

    if (_selectedPrinter != null) {
      await PrinterService.cetakStruk(_selectedPrinter!, _namaCabang, _namaKasir, idTrx, _keranjang, _totalBelanja, bayar, kembali, metode);
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _keranjang.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> produkTampil = _produkList.where((p) => _kategoriAktif == 'Semua' || p['kategori'] == _kategoriAktif).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kasir: $_namaCabang', style: const TextStyle(fontSize: 16)),
            Text('Petugas: $_namaKasir', style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.print), onPressed: _pilihPrinter, tooltip: 'Pilih Printer'),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ['Semua', 'Makanan', 'Minuman'].map((kat) {
                bool isActive = _kategoriAktif == kat;
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: ChoiceChip(
                    label: Text(kat),
                    selected: isActive,
                    onSelected: (val) => setState(() => _kategoriAktif = kat),
                    selectedColor: const Color(0xFFFFF0F0),
                    labelStyle: TextStyle(color: isActive ? const Color(0xFFD32F2F) : Colors.black87, fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: produkTampil.length,
              itemBuilder: (context, index) {
                final produk = produkTampil[index];
                return InkWell(
                  onTap: () => _tambahKeKeranjang(produk),
                  borderRadius: BorderRadius.circular(12),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (produk['gambar'] != null && produk['gambar'] != '')
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(produk['gambar']), height: 50, width: double.infinity, fit: BoxFit.cover),
                            )
                          else
                            const SizedBox(height: 50),
                          Text(produk['nama'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_currencyFormat.format(produk['harga']), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 13)),
                              const Icon(Icons.add_circle, color: Color(0xFFD32F2F), size: 20),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _keranjang.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _bukaKeranjang,
              backgroundColor: const Color(0xFFD32F2F),
              icon: const Icon(Icons.shopping_cart),
              label: Text('${_keranjang.length} Item - ${_currencyFormat.format(_totalBelanja)}'),
            )
          : null,
    );
  }
}
