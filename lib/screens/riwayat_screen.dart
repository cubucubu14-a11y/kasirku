import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<Map<String, dynamic>> _riwayat = [];
  String _filterAktif = 'Semua';
  bool _sedangSinkron = false;
  final NumberFormat _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
  }

  Future<void> _loadRiwayat() async {
    String? dateFilter;
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');
    if (_filterAktif == 'Hari Ini') {
      dateFilter = formatter.format(now);
    } else if (_filterAktif == 'Bulan Ini') {
      dateFilter = formatter.format(now).substring(0, 7);
    } else if (_filterAktif == 'Custom') {
      final picked = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      );
      if (picked == null) return;
      dateFilter = formatter.format(picked);
    }
    final data = await DatabaseHelper.instance.getTransaksi(
      filterTanggal: dateFilter,
    );
    if (mounted) setState(() => _riwayat = data);
  }

  List<Map<String, dynamic>> get _aktif => _riwayat
      .where((trx) => (trx['status_sync'] as num).toInt() != 2)
      .toList();

  int get _omset => _aktif.fold<int>(
        0,
        (sum, trx) => sum + (trx['total'] as num).toInt(),
      );

  int get _omsetTunai => _aktif
      .where((trx) => (trx['metode']?.toString().toLowerCase() ?? 'tunai') == 'tunai')
      .fold<int>(0, (sum, trx) => sum + (trx['total'] as num).toInt());

  int get _omsetQris => _aktif
      .where((trx) {
        final method = trx['metode']?.toString().toLowerCase() ?? '';
        return method == 'qris' || method == 'kris';
      })
      .fold<int>(0, (sum, trx) => sum + (trx['total'] as num).toInt());

  List<MapEntry<String, Map<String, int>>> get _peringkat {
    final products = <String, Map<String, int>>{};
    for (final trx in _aktif) {
      try {
        final items = jsonDecode(trx['items_json']) as List<dynamic>;
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final name = item['nama'].toString();
          final qty = (item['qty'] as num).toInt();
          final price = (item['harga'] as num).toInt();
          final total = products.putIfAbsent(
            name,
            () => <String, int>{'qty': 0, 'nominal': 0},
          );
          total['qty'] = total['qty']! + qty;
          total['nominal'] = total['nominal']! + qty * price;
        }
      } catch (_) {
        // Ignore invalid item JSON for this transaction.
      }
    }
    final result = products.entries.toList()
      ..sort((a, b) {
        final quantityOrder = b.value['qty']!.compareTo(a.value['qty']!);
        return quantityOrder != 0
            ? quantityOrder
            : b.value['nominal']!.compareTo(a.value['nominal']!);
      });
    return result;
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _sync({bool force = false}) async {
    if (_sedangSinkron) return;
    if (force) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sinkronisasi Paksa?'),
              content: const Text(
                'Kirim ulang transaksi aktif dan proses semua perubahan yang masih tertunda.',
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
      if (!confirmed) return;
    }

    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString('url_appscript') ?? '').isEmpty) {
      _message('URL Apps Script belum diisi di menu Pengaturan');
      return;
    }

    setState(() => _sedangSinkron = true);
    try {
      final result = await SyncService.instance.syncPending(force: force);
      await _loadRiwayat();
      _message(result['failed'] == 0
          ? 'Berhasil sinkron ${result['success']} operasi'
          : 'Berhasil ${result['success']}, gagal ${result['failed']}. Periksa URL dan koneksi.');
    } catch (error) {
      _message('Sinkronisasi gagal: $error');
    } finally {
      if (mounted) setState(() => _sedangSinkron = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> trx) async {
    final items = (jsonDecode(trx['items_json']) as List<dynamic>)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    var method = (trx['metode']?.toString() ?? 'Tunai');
    int total() => items.fold<int>(
          0,
          (sum, item) => sum +
              (item['harga'] as num).toInt() * (item['qty'] as num).toInt(),
        );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Edit Transaksi'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item['nama'].toString()),
                      subtitle: Text(
                        _currency.format(item['harga']) + ' per item',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => updateDialog(() {
                              final qty = (item['qty'] as num).toInt();
                              if (qty > 1) {
                                item['qty'] = qty - 1;
                              } else {
                                items.removeAt(index);
                              }
                            }),
                          ),
                          Text('${item['qty']}'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => updateDialog(() {
                              item['qty'] = (item['qty'] as num).toInt() + 1;
                            }),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: ${_currency.format(total())}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: method.toLowerCase() == 'qris' ||
                            method.toLowerCase() == 'kris'
                        ? 'QRIS'
                        : 'Tunai',
                    decoration: const InputDecoration(labelText: 'Pembayaran'),
                    items: const [
                      DropdownMenuItem(value: 'Tunai', child: Text('Tunai')),
                      DropdownMenuItem(value: 'QRIS', child: Text('QRIS')),
                    ],
                    onChanged: (value) {
                      if (value != null) updateDialog(() => method = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: items.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;

    final id = trx['id_transaksi'].toString();
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'action': 'simpanTransaksi',
      'id_transaksi': id,
      'nama_cabang': prefs.getString('nama_cabang') ?? '',
      'nama_kasir': prefs.getString('nama_kasir') ?? '',
      'tanggal': trx['tanggal'].toString(),
      'waktu': trx['waktu'].toString(),
      'metode': method,
      'items': items,
    };
    await DatabaseHelper.instance.editTransaksiOffline({
      'id_transaksi': id,
      'tanggal': trx['tanggal'],
      'waktu': trx['waktu'],
      'total': total(),
      'metode': method,
      'items_json': jsonEncode(items),
      'status_sync': 0,
    }, payload);
    await _loadRiwayat();
    _message('Transaksi diperbarui di aplikasi; sinkron akan berjalan otomatis.');
    SyncService.instance.syncPending();
  }

  Future<void> _delete(Map<String, dynamic> trx) async {
    final id = trx['id_transaksi'].toString();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hapus transaksi?'),
            content: const Text(
              'Transaksi langsung dihapus dari aplikasi. Penghapusan di Sheet akan disinkronkan saat tersedia jaringan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final prefs = await SharedPreferences.getInstance();
    final wasSynced = (trx['status_sync'] as num).toInt() == 1;
    if (wasSynced) {
      await DatabaseHelper.instance.hapusTransaksiOffline(id, {
        'action': 'hapusTransaksi',
        'id_transaksi': id,
        'nama_cabang': prefs.getString('nama_cabang') ?? '',
      });
    } else {
      // A pending create/edit must be cancelled, not later uploaded after deletion.
      await DatabaseHelper.instance.hapusTransaksi(id);
    }
    await _loadRiwayat();
    _message('Transaksi dihapus dari aplikasi.');
    SyncService.instance.syncPending();
  }

  Widget _methodTotal(String name, int amount, Color color, IconData icon) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 12)),
                Text(
                  _currency.format(amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _transactionCard(Map<String, dynamic> trx) {
    final synced = (trx['status_sync'] as num).toInt() == 1;
    final id = trx['id_transaksi'].toString();
    final items = jsonDecode(trx['items_json']) as List<dynamic>;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: synced ? Colors.green : Colors.orange,
          child: Icon(
            synced ? Icons.check : Icons.cloud_upload,
            color: Colors.white,
          ),
        ),
        title: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${trx['tanggal']} | ${trx['waktu']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currency.format(trx['total']),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _edit(trx);
                if (value == 'delete') _delete(trx);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Hapus')),
              ],
            ),
          ],
        ),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Detail Transaksi'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: items.map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  return Text(
                    "${item['qty']}x ${item['nama']} - ${_currency.format(item['harga'])}",
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChart() {
    final ranking = _peringkat;
    if (ranking.isEmpty) {
      _message('Belum ada produk terjual pada periode ini.');
      return;
    }
    final maxQty = ranking.first.value['qty']!.toDouble();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .75,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ranking.length,
            itemBuilder: (context, index) {
              final entry = ranking[index];
              final qty = entry.value['qty']!;
              final share = (qty / maxQty).clamp(0.05, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${index + 1}. ${entry.key} ($qty' 'x)')),
                        Text(_currency.format(entry.value['nominal'])),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) => Container(
                        height: 10,
                        width: constraints.maxWidth * math.min(share, 1.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const filters = ['Semua', 'Hari Ini', 'Bulan Ini', 'Custom'];
    final ranking = _peringkat;
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
              tooltip: 'Sinkron perubahan tertunda',
              onPressed: () => _sync(),
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sinkronisasi paksa',
              onPressed: () => _sync(force: true),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((filter) => Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: _filterAktif == filter,
                  onSelected: (_) {
                    setState(() => _filterAktif = filter);
                    _loadRiwayat();
                  },
                ),
              )).toList(),
            ),
          ),
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Total Omset')),
                      Text(_currency.format(_omset), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(child: _methodTotal('Tunai', _omsetTunai, Colors.green, Icons.payments_outlined)),
                      Expanded(child: _methodTotal('QRIS', _omsetQris, Colors.blue, Icons.qr_code_2)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (ranking.isNotEmpty)
            ListTile(
              title: Text('Terlaris: ${ranking.first.key} (${ranking.first.value['qty']} terjual)'),
              trailing: const Icon(Icons.bar_chart),
              onTap: _showChart,
            ),
          Expanded(
            child: _aktif.isEmpty
                ? const Center(child: Text('Tidak ada riwayat transaksi'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _aktif.length,
                    itemBuilder: (context, index) => _transactionCard(_aktif[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
