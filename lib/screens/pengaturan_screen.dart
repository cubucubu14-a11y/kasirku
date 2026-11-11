import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  String _namaKasir = '';
  String _namaCabang = '';
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
      _namaKasir = prefs.getString('nama_kasir') ?? '';
      _namaCabang = prefs.getString('nama_cabang') ?? '';
      _produkList = produk;
    });
  }

  Future<void> _simpanUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('url_appscript', _urlController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL berhasil disimpan')));
  }

  void _editInfoTokoDialog() {
    final pinC = TextEditingController();
    final kasirC = TextEditingController(text: _namaKasir);
    final cabangC = TextEditingController(text: _namaCabang);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verifikasi PIN'),
        content: TextField(
          controller: pinC,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Masukkan PIN (Default: 123456)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (pinC.text == '123456') {
                Navigator.pop(context);
                _showFormEditToko(kasirC, cabangC);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN Salah!')));
              }
            },
            child: const Text('Buka'),
          )
        ],
      ),
    );
  }

  void _showFormEditToko(TextEditingController kasirC, TextEditingController cabangC) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Info Toko'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: kasirC, decoration: const InputDecoration(labelText: 'Nama Kasir')),
            TextField(controller: cabangC, decoration: const InputDecoration(labelText: 'Nama Cabang')),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('nama_kasir', kasirC.text);
              await prefs.setString('nama_cabang', cabangC.text);
              if (!context.mounted) return;
              Navigator.pop(context);
              _loadData();
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  void _showProdukDialog({Map<String, dynamic>? produk}) {
    final namaC = TextEditingController(text: produk?['nama']);
    final hargaC = TextEditingController(text: produk?['harga'].toString());
    final kategoriC = TextEditingController(text: produk?['kategori'] ?? 'Makanan');
    String? gambarPath = produk?['gambar'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(produk == null ? 'Tambah Produk' : 'Edit Produk'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (gambarPath != null && gambarPath.isNotEmpty)
                    Image.file(File(gambarPath), height: 100, width: 100, fit: BoxFit.cover)
                  else
                    Container(height: 100, width: 100, color: Colors.grey[300], child: const Icon(Icons.image, size: 50)),
                  TextButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                      if (pickedFile != null) setModalState(() => gambarPath = pickedFile.path);
                    },
                    icon: const Icon(Icons.photo),
                    label: const Text('Pilih Gambar'),
                  ),
                  TextField(controller: namaC, decoration: const InputDecoration(labelText: 'Nama Produk')),
                  TextField(controller: hargaC, decoration: const InputDecoration(labelText: 'Harga (Angka)'), keyboardType: TextInputType.number),
                  TextField(controller: kategoriC, decoration: const InputDecoration(labelText: 'Kategori')),
                ],
              );
            }
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (namaC.text.isNotEmpty && hargaC.text.isNotEmpty) {
                final data = {
                  'id': produk?['id'] ?? "P-${DateTime.now().millisecondsSinceEpoch}",
                  'nama': namaC.text,
                  'harga': int.parse(hargaC.text),
                  'kategori': kategoriC.text,
                  'gambar': gambarPath ?? '',
                };
                if (produk == null) {
                  await DatabaseHelper.instance.tambahProduk(data);
                } else {
                  await DatabaseHelper.instance.editProduk(data);
                }
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
          const Text('Informasi Toko', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.store),
              title: Text('Cabang: $_namaCabang'),
              subtitle: Text('Kasir: $_namaKasir'),
              trailing: IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: _editInfoTokoDialog,
              ),
            ),
          ),
          const Divider(height: 32),
          
          const Text('URL Google Apps Script', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _urlController, decoration: const InputDecoration(border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _simpanUrl, child: const Text('Simpan')),
            ],
          ),
          const Divider(height: 32),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Daftar Produk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(onPressed: () => _showProdukDialog(), icon: const Icon(Icons.add), label: const Text('Tambah')),
            ],
          ),
          const SizedBox(height: 8),
          ..._produkList.map((p) => Card(
            child: ListTile(
              leading: (p['gambar'] != null && p['gambar'] != '')
                  ? Image.file(File(p['gambar']), width: 40, height: 40, fit: BoxFit.cover)
                  : const Icon(Icons.fastfood),
              title: Text(p['nama']),
              subtitle: Text('Rp ${p['harga']} | ${p['kategori']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showProdukDialog(produk: p)),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await DatabaseHelper.instance.hapusProduk(p['id']);
                      _loadData();
                    },
                  ),
                ],
              ),
            ),
          )),
          
          const Divider(height: 32),
          ElevatedButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SetupScreen()), (route) => false);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Reset Aplikasi / Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
          )
        ],
      ),
    );
  }
}
