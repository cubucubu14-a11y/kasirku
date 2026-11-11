import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/database_helper.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<Map<String, dynamic>> _riwayat = [];
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
  }

  Future<void> _loadRiwayat() async {
    final data = await DatabaseHelper.instance.getTransaksi();
    setState(() {
      _riwayat = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRiwayat)
        ],
      ),
      body: _riwayat.isEmpty
          ? const Center(child: Text('Belum ada riwayat transaksi'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _riwayat.length,
              itemBuilder: (context, index) {
                final trx = _riwayat[index];
                bool isSynced = trx['status_sync'] == 1;
                
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSynced ? Colors.green : Colors.orange,
                      child: Icon(isSynced ? Icons.check : Icons.cloud_upload, color: Colors.white),
                    ),
                    title: Text('ID: ${trx['id_transaksi']}', style: const TextStyle(fontSize: 12)),
                    subtitle: Text('${trx['tanggal']} | ${trx['waktu']}'),
                    trailing: Text(
                      _currencyFormat.format(trx['total']),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    onTap: () {
                      // Tampilkan detail struk
                      final List items = jsonDecode(trx['items_json']);
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Detail Transaksi'),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                return Text('${item['qty']}x ${item['nama']} - ${_currencyFormat.format(item['harga'])}');
                              },
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
