import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'kasir_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlController = TextEditingController();
  final _kasirController = TextEditingController();
  final _cabangController = TextEditingController();
  bool _isLoading = false;

  Future<void> _simpanPengaturan() async {
    // Hanya Nama Kasir dan Cabang yang WAJIB diisi
    if (_kasirController.text.isEmpty || _cabangController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Kasir dan Cabang harus diisi!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('url_appscript', _urlController.text.trim());
      await prefs.setString('nama_kasir', _kasirController.text.trim());
      await prefs.setString('nama_cabang', _cabangController.text.trim());

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const KasirScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Awal')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.store, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            TextField(
              controller: _kasirController,
              decoration: const InputDecoration(
                labelText: 'Nama Kasir',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cabangController,
              decoration: const InputDecoration(
                labelText: 'Nama Cabang',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.storefront),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL Apps Script (Opsional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _simpanPengaturan,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Simpan & Mulai Kasir', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
