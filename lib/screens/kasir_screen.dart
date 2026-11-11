import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> _prosesBayar() async {
    if (_keranjang.isEmpty) return;
    setState(() => _isLoading = true);

    final now = DateTime.now();
    final tgl = DateFormat('yyyy-MM-dd').format(now);
    final wkt = DateFormat('HH:mm:ss').format(now);
    final idTrx = "TRX-${now.millisecondsSinceEpoch}";
    final total = _totalBelanja;

    // Simpan ke Database HP
    await DatabaseHelper.instance.simpanTransaksi({
      'id_transaksi': idTrx,
      'tanggal': tgl,
      'waktu': wkt,
      'total': total,
      'items_json': jsonEncode(_keranjang),
      'status_sync': 0, // 0 = Belum sinkron
    });

    // Coba kirim ke AppScript jika URL ada
    if (_urlAppScript.isNotEmpty) {
      bool sukses = await ApiService.kirimTransaksi(_urlAppScript, _namaCabang, _namaKasir, _keranjang);
      if (sukses) {
        await DatabaseHelper.instance.updateStatusSync(idTrx);
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _keranjang.clear();
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pembayaran Berhasil'),
        content: Text('Total: ${_currencyFormat.format(total)}\nData tersimpan di HP.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _bukaKeranjang() {
    if (_keranjang.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keranjang masih kosong!')));
      return;
    }

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
                            title: Text(item['nama'], style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      onPressed: _isLoading ? null : () {
                        Navigator.pop(context);
                        _prosesBayar();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
                      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('BAYAR SEKARANG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> produkTampil = _produkList.where((p) => _kategoriAktif == 'Semua' || p['kategori'] == _kategoriAktif).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kasir: $_namaCabang', style: const TextStyle(fontSize: 16)),
            Text('Petugas: $_namaKasir', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter Kategori
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isActive ? const Color(0xFFD32F2F) : Colors.transparent)),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Grid Produk
          Expanded(
            child: produkTampil.isEmpty
                ? const Center(child: Text('Produk tidak ditemukan'))
                : GridView.builder(
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
                                Text(produk['nama'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_currencyFormat.format(produk['harga']), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle),
                                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                                    )
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
