import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/database_helper.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<Map<String, dynamic>> _riwayat = [];
  String _filterAktif = 'Semua';
  String _filterProduk = '';
  bool _sedangSinkron = false;
  final TextEditingController _productSearchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    super.dispose();
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
      final picked = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      );
      if (picked == null) return;
      tanggalFilter = formatter.format(picked);
    }

    final data = await DatabaseHelper.instance.getTransaksi(
      filterTanggal: tanggalFilter,
    );
    if (!mounted) return;
    setState(() => _riwayat = data);
  }

  List<Map<String, dynamic>> get _transaksiAktif => _riwayat
      .where((trx) => (trx['status_sync'] as num).toInt() != 2)
      .toList();

  int get _totalOmset => _transaksiAktif.fold<int>(
        0,
        (sum, trx) => sum + (trx['total'] as num).toInt(),
      );

  int get _totalTunai => _transaksiAktif
      .where((trx) => (trx['metode']?.toString().toLowerCase() ?? 'tunai') == 'tunai')
      .fold<int>(0, (sum, trx) => sum + (trx['total'] as num).toInt());

  int get _totalQris => _transaksiAktif
      .where((trx) {
        final metode = trx['metode']?.toString().toLowerCase() ?? '';
        return metode == 'qris' || metode == 'kris';
      })
      .fold<int>(0, (sum, trx) => sum + (trx['total'] as num).toInt());

  List<MapEntry<String, Map<String, int>>> get _peringkatProduk {
    final sales = <String, Map<String, int>>{};
    for (final trx in _transaksiAktif) {
      try {
        final items = jsonDecode(trx['items_json']) as List<dynamic>;
        for (final rawItem in items) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          final name = item['nama'].toString();
          if (_filterProduk.isNotEmpty &&
              !name.toLowerCase().contains(_filterProduk.toLowerCase())) {
            continue;
          }
          final qty = (item['qty'] as num).toInt();
          final price = (item['harga'] as num).toInt();
          final totals = sales.putIfAbsent(
            name,
            () => <String, int>{'qty': 0, 'nominal': 0},
          );
          totals['qty'] = totals['qty']! + qty;
          totals['nominal'] = totals['nominal']! + price * qty;
        }
      } catch (_) {
        // Ignore invalid item JSON without hiding other history entries.
      }
    }
    final result = sales.entries.toList()
      ..sort((a, b) {
        final byQty = b.value['qty']!.compareTo(a.value['qty']!);
        return byQty != 0
            ? byQty
            : b.value['nominal']!.compareTo(a.value['nominal']!);
      });
    return result;
  }

  bool _containsFilteredProduct(Map<String, dynamic> trx) {
    if (_filterProduk.isEmpty) return true;
    try {
      final items = jsonDecode(trx['items_json']) as List<dynamic>;
      return items.any((item) => item['nama']
          .toString()
          .toLowerCase()
          .contains(_filterProduk.toLowerCase()));
    } catch (_) {
      return false;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _sinkronSemua({bool paksa = false}) async {
    if (_sedangSinkron) return;
    if (paksa) {
      final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sinkronisasi Paksa?'),
              content: const Text(
                'Semua transaksi selain VOID akan dikirim ulang. Apps Script akan mengabaikan ID transaksi yang sudah ada agar tidak membuat duplikat.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Sinkronkan'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirm) return;
    }

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final cabang = prefs.getString('nama_cabang') ?? '';
    final kasir = prefs.getString('nama_kasir') ?? '';
    if (url.isEmpty) {
      _snack('URL Apps Script belum diisi di menu Pengaturan');
      return;
    }

    final List<Map<String, dynamic>> targets;
    if (paksa) {
      final all = await DatabaseHelper.instance.getTransaksi();
      targets = all
          .where((trx) => (trx['status_sync'] as num).toInt() != 2)
          .toList();
    } else {
      targets = await DatabaseHelper.instance.getTransaksiBelumSync();
    }

    if (targets.isEmpty) {
      _snack(paksa
          ? 'Tidak ada transaksi aktif untuk dikirim'
          : 'Semua transaksi sudah tersinkron');
      return;
    }

    setState(() => _sedangSinkron = true);
    var berhasil = 0;
    var gagal = 0;
    var errorTerakhir = '';

    try {
      for (final trx in targets) {
        try {
          final decoded = jsonDecode(trx['items_json']) as List<dynamic>;
          final items = decoded
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          final sukses = await ApiService.kirimTransaksi(
            url,
            cabang,
            kasir,
            items,
            trx['metode']?.toString(),
            idTransaksi: trx['id_transaksi'].toString(),
            tanggal: trx['tanggal'].toString(),
            waktu: trx['waktu'].toString(),
          );
          if (sukses) {
            await DatabaseHelper.instance.updateStatusSync(
              trx['id_transaksi'].toString(),
            );
            berhasil++;
          } else {
            gagal++;
            errorTerakhir = ApiService.lastError;
          }
        } catch (error) {
          gagal++;
          errorTerakhir = error.toString();
        }
      }
    } finally {
      if (mounted) setState(() => _sedangSinkron = false);
    }

    await _loadRiwayat();
    if (gagal == 0) {
      _snack('Berhasil sinkron $berhasil transaksi');
    } else {
      _snack('Berhasil $berhasil, gagal $gagal. Error: $errorTerakhir');
    }
  }

  Future<void> _prosesVoid(String idTrx, String statusSync) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Batalkan Transaksi?'),
            content: const Text(
              'Transaksi akan ditandai VOID di aplikasi dan Google Sheets. Barisnya tetap disimpan sebagai catatan, bukan dihapus.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('VOID'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    // If already synced, only mark locally after the server confirms the VOID.
    if (statusSync == '1') {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('url_appscript') ?? '';
      final cabang = prefs.getString('nama_cabang') ?? '';
      if (url.isEmpty) {
        _snack('VOID gagal: URL Apps Script belum diisi');
        return;
      }
      final success = await ApiService.voidTransaksi(url, cabang, idTrx);
      if (!success) {
        _snack('VOID gagal: ${ApiService.lastError}');
        return;
      }
    }

    await DatabaseHelper.instance.voidTransaksiLokal(idTrx);
    await _loadRiwayat();
  }

  Widget _buildOmsetMetode(String label, int amount, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(
                _currencyFormat.format(amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> trx) {
    final status = (trx['status_sync'] as num).toInt();
    final isVoid = status == 2;
    final isSynced = status == 1;
    final id = trx['id_transaksi'].toString();
    return Card(
      color: isVoid ? Colors.grey[300] : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isVoid
              ? Colors.grey
              : (isSynced ? Colors.green : Colors.orange),
          child: Icon(
            isVoid ? Icons.cancel : (isSynced ? Icons.check : Icons.cloud_upload),
            color: Colors.white,
          ),
        ),
        title: Text(
          'ID: $id',
          style: TextStyle(
            fontSize: 12,
            decoration: isVoid ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text('${trx['tanggal']} | ${trx['waktu']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isVoid ? 'VOID' : _currencyFormat.format(trx['total']),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isVoid ? Colors.red : Colors.black,
              ),
            ),
            if (!isVoid)
              IconButton(
                icon: const Icon(Icons.block, color: Colors.red),
                tooltip: 'Void Transaksi',
                onPressed: () => _prosesVoid(id, status.toString()),
              ),
          ],
        ),
        onTap: () {
          final items = jsonDecode(trx['items_json']) as List<dynamic>;
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Detail Transaksi'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;
                    return Text(
                      '${item['qty']}x ${item['nama']} - ${_currencyFormat.format(item['harga'])}',
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _riwayat.where(_containsFilteredProduct).toList();
    const filters = ['Semua', 'Hari Ini', 'Bulan Ini', 'Custom'];
    final ranking = _peringkatProduk;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          if (_sedangSinkron)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.cloud_sync),
              tooltip: 'Sinkron transaksi yang tertunda',
              onPressed: () => _sinkronSemua(),
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sinkronisasi paksa: kirim ulang semua transaksi aktif',
              onPressed: () => _sinkronSemua(paksa: true),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((filter) {
                  final active = _filterAktif == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: active,
                      onSelected: (_) {
                        setState(() => _filterAktif = filter);
                        _loadRiwayat();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFFD32F2F)),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Total Omset')),
                      Text(
                        _currencyFormat.format(_totalOmset),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildOmsetMetode(
                          'Tunai', _totalTunai, Icons.payments_outlined, Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOmsetMetode(
                          'QRIS', _totalQris, Icons.qr_code_2, Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextField(
              controller: _productSearchController,
              decoration: InputDecoration(
                labelText: 'Filter nama produk / produk terlaris',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filterProduk.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _productSearchController.clear();
                          setState(() => _filterProduk = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _filterProduk = value.trim()),
            ),
          ),
          if (ranking.isNotEmpty)
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: ranking.length,
                itemBuilder: (context, index) {
                  final entry = ranking[index];
                  return SizedBox(
                    width: 220,
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${entry.value['qty']} terjual'),
                        trailing: Text(_currencyFormat.format(entry.value['nominal'])),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: transactions.isEmpty
                ? const Center(child: Text('Tidak ada riwayat transaksi'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) =>
                        _buildTransactionCard(transactions[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
