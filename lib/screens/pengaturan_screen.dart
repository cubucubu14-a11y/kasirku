import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';
import 'setup_screen.dart';

class PengaturanScreen extends StatefulWidget {
  const PengaturanScreen({super.key});

  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  final _urlController = TextEditingController();
  List<Map<String, dynamic>> _produkList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final produk = await DatabaseHelper.instance.getProduk();
    setState(() {
      _urlController.text = prefs.getString('url_appscript') ?? '';
      _produkList = produk;
    });
  }

  Future<void> _simpanUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('url_appscript', _urlController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL berhasil disimpan')));
  }

  void _tambahProdukDialog() {
    final namaC = TextEditingController();
    final hargaC = TextEditingController();
    final kategoriC = TextEditingController(text: 'Makanan');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Produk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: namaC, decoration: const InputDecoration(labelText: 'Nama Produk')),
            TextField(controller: hargaC, decoration: const InputDecoration(labelText: 'Harga (Angka)'), keyboardType: TextInputType.number),
            TextField(controller: kategoriC, decoration: const InputDecoration(labelText: 'Kategori (Makanan/Minuman)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (namaC.text.isNotEmpty && hargaC.text.isNotEmpty) {
                await DatabaseHelper.instance.tambahProduk({
                  'id': "P-${DateTime.now().millisecondsSinceEpoch}",
                  'nama': namaC.text,
                  'harga': int.parse(hargaC.text),
                  'kategori': kategoriC.text,
                });
                if (!context.mounted) return;
                Navigator.pop(context);
                _loadData();
              }
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('URL Google Apps Script', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _urlController, decoration: const InputDecoration(border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _simpanUrl, child: const Text('Simpan')),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Daftar Produk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(onPressed: _tambahProdukDialog, icon: const Icon(Icons.add), label: const Text('Tambah')),
            ],
          ),
          const SizedBox(height: 8),
          ..._produkList.map((p) => Card(
            child: ListTile(
              title: Text(p['nama']),
              subtitle: Text('Rp ${p['harga']} | ${p['kategori']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  await DatabaseHelper.instance.hapusProduk(p['id']);
                  _loadData();
                },
              ),
            ),
          )),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const SetupScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
            label: const Text('Reset Aplikasi / Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          )
        ],
      ),
    );
  }
}
