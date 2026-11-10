import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/api_service.dart';
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
  String _kategoriAktif = 'Semua';
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  // Data dummy dengan gambar placeholder (karena belum ada database produk)
  final List<Map<String, dynamic>> _produkList = [
    {'id': 'P001', 'nama': 'Kopi Susu Gula Aren', 'harga': 20000, 'kategori': 'Minuman', 'gambar': 'https://picsum.photos/200/200?random=1'},
    {'id': 'P002', 'nama': 'Roti Bakar Coklat', 'harga': 15000, 'kategori': 'Makanan', 'gambar': 'https://picsum.photos/200/200?random=2'},
    {'id': 'P003', 'nama': 'Nasi Goreng Spesial', 'harga': 25000, 'kategori': 'Makanan', 'gambar': 'https://picsum.photos/200/200?random=3'},
    {'id': 'P004', 'nama': 'Es Teh Manis', 'harga': 5000, 'kategori': 'Minuman', 'gambar': 'https://picsum.photos/200/200?random=4'},
    {'id': 'P005', 'nama': 'Ayam Geprek', 'harga': 18000, 'kategori': 'Makanan', 'gambar': 'https://picsum.photos/200/200?random=5'},
    {'id': 'P006', 'nama': 'Air Mineral', 'harga': 4000, 'kategori': 'Minuman', 'gambar': 'https://picsum.photos/200/200?random=6'},
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
    setState(() => _pendingCount = antrean.length);
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

  Future<void> _prosesBayar() async {
    if (_keranjang.isEmpty) return;
    setState(() => _isLoading = true);

    final dataTransaksi = {
      "nama_cabang": _namaCabang,
      "nama_kasir": _namaKasir,
      "items": _keranjang,
    };

    await DatabaseHelper.instance.simpanAntrean(dataTransaksi);
    await _sinkronisasiData();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pembayaran Berhasil'),
        content: Text('Total: ${_currencyFormat.format(_totalBelanja)}\nData tersimpan aman.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _keranjang.clear());
            },
            child: const Text('TUTUP'),
          ),
        ],
      ),
    );
    setState(() => _isLoading = false);
  }

  // ==========================================
  // TAMPILAN KIRI: DAFTAR PRODUK & KATEGORI
  // ==========================================
  Widget _buildPanelKiri() {
    List<Map<String, dynamic>> produkTampil = _produkList.where((p) => _kategoriAktif == 'Semua' || p['kategori'] == _kategoriAktif).toList();

    return Expanded(
      flex: 3, // Mengambil 60% lebar layar di tablet
      child: Container(
        color: const Color(0xFFF5F6F8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Kategori
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isActive ? const Color(0xFFD32F2F) : Colors.transparent)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            
            // Grid Produk
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180, // Ukuran maksimal lebar kartu
                  childAspectRatio: 0.85, 
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
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gambar Produk (Placeholder)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: Image.network(
                              produk['gambar'],
                              height: 100,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(height: 100, color: Colors.grey[300], child: const Icon(Icons.image, color: Colors.grey)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(produk['nama'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(_currencyFormat.format(produk['harga']), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAMPILAN KANAN: KERANJANG PESANAN
  // ==========================================
  Widget _buildPanelKanan() {
    return Expanded(
      flex: 2, // Mengambil 40% lebar layar di tablet
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pesanan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Meja 3', style: TextStyle(color: Colors.grey[600])), // Dummy UI
                ],
              ),
            ),
            const Divider(height: 1),
            
            // List Pesanan
            Expanded(
              child: _keranjang.isEmpty
                  ? const Center(child: Text('Belum ada pesanan', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _keranjang.length,
                      itemBuilder: (context, index) {
                        final item = _keranjang[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                          child: Row(
                            children: [
                              // Qty & Tombol +/- (Kustom)
                              Column(
                                children: [
                                  InkWell(
                                    onTap: () => _tambahKeKeranjang(item),
                                    child: const Icon(Icons.keyboard_arrow_up, color: Color(0xFFD32F2F)),
                                  ),
                                  Text('${item['qty']}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  InkWell(
                                    onTap: () => _kurangiKeranjang(index),
                                    child: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              
                              // Info Produk
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['nama'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text(_currencyFormat.format(item['harga']), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                  ],
                                ),
                              ),
                              
                              // Total Harga Item
                              Text(_currencyFormat.format((item['harga'] as int) * (item['qty'] as int)), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Panel Bawah (Total & Bayar)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(_currencyFormat.format(_totalBelanja), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _keranjang.isEmpty ? null : _prosesBayar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F), // Warna merah menyala
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text('Tagih - ${_currencyFormat.format(_totalBelanja)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // ==========================================
  // LAYOUT UTAMA (Responsif HP vs Tablet)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    // Cek apakah layar lebar (Tablet) atau sempit (HP)
    bool isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: isTablet 
          ? null // Sembunyikan AppBar di Tablet (seperti gambar referensi)
          : AppBar(
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
                    IconButton(icon: const Icon(Icons.sync), onPressed: _isLoading ? null : _sinkronisasiData),
                    if (_pendingCount > 0)
                      Positioned(
                        right: 4, top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text('$_pendingCount', style: const TextStyle(color: Colors.white, fontSize: 10)),
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
      
      // Jika Tablet, pakai Row (Kiri Kanan). Jika HP, cukup tampilkan Kiri (Kanan jadi Bottom Sheet)
      body: isTablet 
          ? Row(
              children: [
                _buildPanelKiri(),
                _buildPanelKanan(), // Panel kanan langsung tampil di sebelah kanan
              ],
            )
          : _buildPanelKiri(), // Di HP, hanya tampil produk

      // Tombol Keranjang Melayang untuk HP
      floatingActionButton: !isTablet && _keranjang.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (context) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: _buildPanelKanan(), // Panggil panel kanan di dalam bottom sheet
                  ),
                ).then((_) => setState(() {})); // Refresh saat ditutup
              },
              backgroundColor: const Color(0xFFD32F2F),
              icon: const Icon(Icons.shopping_cart),
              label: Text('${_keranjang.length} Item - ${_currencyFormat.format(_totalBelanja)}'),
            )
          : null,
    );
  }
}
