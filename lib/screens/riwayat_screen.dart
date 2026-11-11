import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/database_helper.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<Map<String, dynamic>> _riwayat = [];
  String _filterAktif = 'Semua';
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
  }

  Future<void> _loadRiwayat() async {
    String? tanggalFilter;
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');

    if (_filterAktif == 'Hari Ini') {
      tanggalFilter = formatter.format(now);
    } else if (_filterAktif == 'Bulan Ini') {
      tanggalFilter = formatter.format(now).substring(0, 7); 
    } else if (_filterAktif == 'Custom') {
      final picked = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2020), lastDate: DateTime(2030));
      if (picked != null) tanggalFilter = formatter.format(picked);
      else return;
    }

    final data = await DatabaseHelper.instance.getTransaksi(filterTanggal: tanggalFilter);
    
    if (_filterAktif == 'Bulan Ini' && tanggalFilter != null) {
      final filtered = data.where((t) => t['tanggal'].toString().startsWith(tanggalFilter)).toList();
      setState(() => _riwayat = filtered);
    } else {
      setState(() => _riwayat = data);
    }
  }

  void _prosesVoid(String idTrx, String statusSync) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan Transaksi?'),
        content: const Text('Transaksi ini akan ditandai sebagai VOID dan tidak bisa dikembalikan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('VOID')),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await DatabaseHelper.instance.voidTransaksiLokal(idTrx);
      
      if (statusSync == '1') {
        final prefs = await SharedPreferences.getInstance();
        final url = prefs.getString('url_appscript') ?? '';
        final cabang = prefs.getString('nama_cabang') ?? '';
        if (url.isNotEmpty) await ApiService.voidTransaksi(url, cabang, idTrx);
      }
      _loadRiwayat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Semua', 'Hari Ini', 'Bulan Ini', 'Custom'].map((filter) {
                  bool isActive = _filterAktif == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: isActive,
                      onSelected: (val) {
                        setState(() => _filterAktif = filter);
                        _loadRiwayat();
                      },
                      selectedColor: const Color(0xFFFFF0F0),
                      labelStyle: TextStyle(color: isActive ? const Color(0xFFD32F2F) : Colors.black87, fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          Expanded(
            child: _riwayat.isEmpty
                ? const Center(child: Text('Tidak ada riwayat transaksi'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _riwayat.length,
                    itemBuilder: (context, index) {
                      final trx = _riwayat[index];
                      int status = trx['status_sync'];
                      bool isVoid = status == 2;
                      bool isSynced = status == 1;
                      
                      return Card(
                        color: isVoid ? Colors.grey[300] : Colors.white,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isVoid ? Colors.grey : (isSynced ? Colors.green : Colors.orange),
                            child: Icon(isVoid ? Icons.cancel : (isSynced ? Icons.check : Icons.cloud_upload), color: Colors.white),
                          ),
                          title: Text('ID: ${trx['id_transaksi']}', style: TextStyle(fontSize: 12, decoration: isVoid ? TextDecoration.lineThrough : null)),
                          subtitle: Text('${trx['tanggal']} | ${trx['waktu']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isVoid ? 'VOID' : _currencyFormat.format(trx['total']),
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isVoid ? Colors.red : Colors.black),
                              ),
                              if (!isVoid)
                                IconButton(
                                  icon: const Icon(Icons.block, color: Colors.red),
                                  tooltip: 'Void Transaksi',
                                  onPressed: () => _prosesVoid(trx['id_transaksi'], status.toString()),
                                )
                            ],
                          ),
                          onTap: () {
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
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
