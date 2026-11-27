import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../services/printer_service.dart';
import '../utils/product_image_storage.dart';
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
  List<BluetoothDevice> _printers = [];
  String? _selectedPrinterAddress;
  bool _loadingPrinters = false;
  bool _isLoadingTarik = false;
  
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPrinters();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final produk = await DatabaseHelper.instance.getProduk();
    final savedPin = prefs.getString('owner_pin');
    if (savedPin != null && savedPin.isNotEmpty) {
      ApiService.setOwnerPin(savedPin);
    }
    if (!mounted) return;
    setState(() {
      _urlController.text = prefs.getString('url_appscript') ?? '';
      _namaKasir = prefs.getString('nama_kasir') ?? '';
      _namaCabang = prefs.getString('nama_cabang') ?? '';
      _produkList = produk;
      _selectedPrinterAddress = prefs.getString('printer_address');
      _isOwner = prefs.getBool('is_owner') ?? false;
    });
  }

  Future<void> _loadPrinters() async {
    setState(() => _loadingPrinters = true);
    final devices = await PrinterService.getPrinters();
    if (!mounted) return;
    setState(() {
      _printers = devices;
      _loadingPrinters = false;
    });
  }

  Future<void> _selectPrinter(String? address) async {
    final prefs = await SharedPreferences.getInstance();
    if (address == null) {
      await prefs.remove('printer_address');
      await prefs.remove('printer_name');
    } else {
      final printer = _printers.firstWhere((device) => device.address == address);
      await prefs.setString('printer_address', printer.address);
      await prefs.setString('printer_name', printer.name ?? 'Printer');
    }
    if (mounted) setState(() => _selectedPrinterAddress = address);
  }

  Future<void> _simpanUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('url_appscript', _urlController.text.trim());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL berhasil disimpan')));
  }

  Future<void> _tarikData() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final branch = prefs.getString('nama_cabang') ?? '';
    
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL Apps Script kosong!')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tarik Semua Data?'),
        content: const Text('Data dari Google Sheets akan dimasukkan ke HP. Proses ini mungkin memakan waktu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tarik')),
        ],
      ),
    ) ?? false;
    if (!confirm) return;

    setState(() => _isLoadingTarik = true);
    final result = await ApiService.tarikSemuaData(url, branch);
    
    if (!mounted) return;
    setState(() => _isLoadingTarik = false);

    if (result != null) {
      int count = 0;
      for (var trx in result) {
        try {
          String itemsJson = trx['detail_produk'] ?? '[]';
          if (itemsJson == '' || !itemsJson.startsWith('[')) {
            itemsJson = jsonEncode([{'nama': 'Tarik dari Sheet', 'qty': 1, 'harga': trx['total']}]);
          }

          await DatabaseHelper.instance.simpanTransaksi({
            'id_transaksi': trx['id_transaksi'],
            'tanggal': trx['tanggal'],
            'waktu': trx['waktu'],
            'total': trx['total'],
            'metode': trx['metode'],
            'items_json': itemsJson, 
            'status_sync': 1,
          });
          count++;
        } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Berhasil menarik $count transaksi baru')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menarik data: ${ApiService.lastError}')));
    }
  }

  void _editInfoTokoDialog() {
    if (!_isOwner) return;

    final kasirC = TextEditingController(text: _namaKasir);
    final cabangC = TextEditingController(text: _namaCabang);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Info Toko'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: kasirC, decoration: const InputDecoration(labelText: 'Nama Kasir')),
            TextField(controller: cabangC, decoration: const InputDecoration(labelText: 'Nama Cabang')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              kasirC.dispose(); cabangC.dispose();
              Navigator.pop(ctx);
            }, 
            child: const Text('Batal')
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('nama_kasir', kasirC.text.trim());
              await prefs.setString('nama_cabang', cabangC.text.trim());
              kasirC.dispose();
              cabangC.dispose();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              await _loadData();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _loginOwnerDialog() {
    final pinC = TextEditingController();
    bool loading = false;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Masuk Mode Owner'),
            content: TextField(
              controller: pinC,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Masukkan PIN Owner', border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              ElevatedButton(
                onPressed: loading ? null : () async {
                  setDialogState(() => loading = true);
                  final prefs = await SharedPreferences.getInstance();
                  final url = prefs.getString('url_appscript') ?? '';
                  final branch = prefs.getString('nama_cabang') ?? '';
                  
                  if (url.isEmpty) {
                    setDialogState(() => loading = false);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL Apps Script kosong!')));
                    return;
                  }
                  
                  final ok = await ApiService.cekPinOwner(url, branch, pinC.text);
                  setDialogState(() => loading = false);
                  
                  if (ok) {
                    await prefs.setBool('is_owner', true);
                    await prefs.setString('owner_pin', pinC.text.trim());
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    setState(() => _isOwner = true);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Berhasil masuk Mode Owner')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.lastError.isEmpty ? 'PIN Salah' : ApiService.lastError)));
                  }
                },
                child: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login'),
              ),
            ],
          );
        }
      ),
    ).whenComplete(() => pinC.dispose());
  }

  void _logoutOwner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_owner', false);
    await prefs.remove('owner_pin');
    ApiService.clearOwnerPin();
    if (mounted) setState(() => _isOwner = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kembali ke Mode Kasir')));
  }

  void _showProdukDialog({Map<String, dynamic>? produk}) {
    if (!_isOwner) return;

    final namaC = TextEditingController(text: produk?['nama']);
    final hargaC = TextEditingController(text: produk?['harga'].toString());
    final kategoriC = TextEditingController(text: produk?['kategori'] ?? 'Makanan');
    String? gambarPath = produk?['gambar'];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(produk == null ? 'Tambah Produk' : 'Edit Produk'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setModalState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (gambarPath != null && gambarPath!.isNotEmpty)
                  Image.file(File(gambarPath!), height: 100, width: 100, fit: BoxFit.cover)
                else
                  Container(height: 100, width: 100, color: Colors.grey[300], child: const Icon(Icons.image, size: 50)),
                
                TextButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      final permanentPath = await saveProductImage(picked.path);
                      if (permanentPath != null) {
                        setModalState(() => gambarPath = permanentPath);
                      }
                    }
                  },
                  icon: const Icon(Icons.photo),
                  label: const Text('Pilih Gambar'),
                ),
                
                TextField(controller: namaC, decoration: const InputDecoration(labelText: 'Nama Produk')),
                TextField(controller: hargaC, decoration: const InputDecoration(labelText: 'Harga (Angka)'), keyboardType: TextInputType.number),
                TextField(controller: kategoriC, decoration: const InputDecoration(labelText: 'Kategori')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              namaC.dispose(); hargaC.dispose(); kategoriC.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nama = namaC.text.trim();
              final kategori = kategoriC.text.trim();
              final hargaText = hargaC.text.trim();
              final harga = int.tryParse(hargaText);
              if (nama.isEmpty || kategori.isEmpty || harga == null || harga < 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi nama, kategori, dan harga berupa angka bulat tidak negatif.')));
                return;
              }
              final data = {
                'id': produk?['id'] ?? 'P-${DateTime.now().millisecondsSinceEpoch}',
                'nama': nama,
                'harga': harga,
                'kategori': kategori,
                'gambar': gambarPath ?? '',
              };
              if (produk == null) {
                await DatabaseHelper.instance.tambahProduk(data);
              } else {
                await DatabaseHelper.instance.editProduk(data);
              }
              namaC.dispose(); hargaC.dispose(); kategoriC.dispose();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              await _loadData();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan'), backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_isOwner)
            Card(
              color: Colors.orange[50],
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                title: const Text('Mode Kasir', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Klik untuk masuk sebagai Owner'),
                trailing: ElevatedButton(
                  onPressed: _loginOwnerDialog,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('Login Owner', style: TextStyle(color: Colors.white)),
                ),
              ),
            )
          else
            Card(
              color: Colors.green[50],
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.green),
                title: const Text('Mode Owner Aktif', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                trailing: TextButton(
                  onPressed: _logoutOwner,
                  child: const Text('Logout Owner'),
                ),
              ),
            ),
          const SizedBox(height: 16),

          _sectionTitle('Informasi Toko'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.store),
              title: Text('Cabang: $_namaCabang'),
              subtitle: Text('Kasir: $_namaKasir'),
              trailing: _isOwner ? IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: _editInfoTokoDialog) : null,
            ),
          ),
          const Divider(height: 32),
          
          _sectionTitle('Daftar Produk'),
          if (_isOwner)
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(onPressed: () => _showProdukDialog(), icon: const Icon(Icons.add), label: const Text('Tambah Produk')),
            ),
          const SizedBox(height: 8),
          ..._produkList.map((p) => Card(
                child: ListTile(
                  leading: p['gambar'] != null && p['gambar'] != ''
                      ? Image.file(File(p['gambar']), width: 40, height: 40, fit: BoxFit.cover)
                      : const Icon(Icons.fastfood),
                  title: Text(p['nama']),
                  subtitle: Text('Rp ${p['harga']} | ${p['kategori']}'),
                  trailing: _isOwner ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showProdukDialog(produk: p)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await DatabaseHelper.instance.hapusProduk(p['id']);
                          await _loadData();
                        },
                      ),
                    ],
                  ) : null,
                ),
              )),
          const Divider(height: 32),
          
          _sectionTitle('Printer Thermal Bluetooth 58mm'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: const Text('Printer paired'),
                  subtitle: Text(_loadingPrinters ? 'Memuat perangkat...' : 'Pair printer melalui pengaturan Bluetooth HP, lalu pilih di bawah.'),
                  trailing: IconButton(icon: const Icon(Icons.refresh), tooltip: 'Muat ulang perangkat paired', onPressed: _loadPrinters),
                ),
                if (_printers.isEmpty && !_loadingPrinters)
                  const Padding(padding: EdgeInsets.all(12), child: Text('Tidak ada perangkat paired.')),
                ..._printers.map((printer) => RadioListTile<String>(
                      value: printer.address,
                      groupValue: _selectedPrinterAddress,
                      onChanged: _selectPrinter,
                      title: Text(printer.name ?? 'Printer'),
                      subtitle: Text(printer.address),
                    )),
                if (_selectedPrinterAddress != null)
                  ListTile(leading: const Icon(Icons.link_off), title: const Text('Lepas pilihan printer'), onTap: () => _selectPrinter(null)),
              ],
            ),
          ),
          const Divider(height: 32),
          
          _sectionTitle('URL Google Apps Script'),
          TextField(controller: _urlController, decoration: const InputDecoration(labelText: 'URL Web App (/exec)', border: OutlineInputBorder()), readOnly: !_isOwner),
          if (_isOwner) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: ElevatedButton(onPressed: _simpanUrl, child: const Text('Simpan URL'))),
          ],
          
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoadingTarik ? null : _tarikData,
            icon: _isLoadingTarik ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.download),
            label: const Text('Tarik Data dari Server (HP Baru)'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), minimumSize: const Size(double.infinity, 0)),
          ),
          
          const Divider(height: 32),
          ElevatedButton.icon(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const SetupScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
            label: const Text('Reset Aplikasi / Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ],
      ),
    );
  }
}
