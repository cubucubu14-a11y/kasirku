import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
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
  String _filterProduk = '';
  bool _sedangSinkron = false;
  final TextEditingController _productSearchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() { super.initState(); _loadRiwayat(); }
  @override
  void dispose() { _productSearchController.dispose(); super.dispose(); }

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
      if (picked == null) return;
      tanggalFilter = formatter.format(picked);
    }
    final data = await DatabaseHelper.instance.getTransaksi(filterTanggal: tanggalFilter);
    if (!mounted) return;
    setState(() => _riwayat = data);
  }

  List<Map<String, dynamic>> get _transaksiAktif => _riwayat.where((t) => (t['status_sync'] as num).toInt() != 2).toList();
  List<Map<String, dynamic>> get _transaksiTerfilter => _transaksiAktif.where(_containsFilteredProduct).toList();
  int get _totalOmset => _transaksiTerfilter.fold<int>(0, (sum, t) => sum + (t['total'] as num).toInt());
  int get _totalTunai => _transaksiTerfilter.where((t) => (t['metode']?.toString().toLowerCase() ?? 'tunai') == 'tunai').fold<int>(0, (sum, t) => sum + (t['total'] as num).toInt());
  int get _totalQris => _transaksiTerfilter.where((t) { final method = t['metode']?.toString().toLowerCase() ?? ''; return method == 'qris' || method == 'kris'; }).fold<int>(0, (sum, t) => sum + (t['total'] as num).toInt());

  List<MapEntry<String, Map<String, int>>> get _peringkatProduk {
    final sales = <String, Map<String, int>>{};
    for (final trx in _transaksiAktif) {
      try {
        final items = jsonDecode(trx['items_json']) as List<dynamic>;
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final name = item['nama'].toString();
          if (_filterProduk.isNotEmpty && !name.toLowerCase().contains(_filterProduk.toLowerCase())) continue;
          final qty = (item['qty'] as num).toInt();
          final price = (item['harga'] as num).toInt();
          final totals = sales.putIfAbsent(name, () => {'qty': 0, 'nominal': 0});
          totals['qty'] = totals['qty']! + qty;
          totals['nominal'] = totals['nominal']! + price * qty;
        }
      } catch (_) {}
    }
    final result = sales.entries.toList()..sort((a, b) {
      final byQty = b.value['qty']!.compareTo(a.value['qty']!);
      return byQty != 0 ? byQty : b.value['nominal']!.compareTo(a.value['nominal']!);
    });
    return result;
  }

  bool _containsFilteredProduct(Map<String, dynamic> trx) {
    if (_filterProduk.isEmpty) return true;
    try {
      final items = jsonDecode(trx['items_json']) as List<dynamic>;
      return items.any((item) => item['nama'].toString().toLowerCase().contains(_filterProduk.toLowerCase()));
    } catch (_) { return false; }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sinkronSemua({bool paksa = false}) async {
    if (_sedangSinkron) return;
    if (paksa) {
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Sinkronisasi Paksa?'),
        content: const Text('Kirim ulang transaksi aktif. Apps Script harus mengenali ID transaksi untuk mencegah duplikat.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sinkronkan'))],
      )) ?? false;
      if (!confirm) return;
    }
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    if (url.isEmpty) { _snack('URL Apps Script belum diisi di menu Pengaturan'); return; }

    setState(() => _sedangSinkron = true);
    Map<String, int> result = {'success': 0, 'failed': 0};
    String lastError = '';
    try {
      // Semua sinkronisasi (termasuk paksa) lewat SyncService agar konsisten
      // dan tetap memakai outbox (upsert/delete).
      result = await SyncService.instance.syncPending(force: paksa);
    } catch (e) {
      lastError = e.toString();
    } finally {
      if (mounted) setState(() => _sedangSinkron = false);
    }
    await _loadRiwayat();
    if (result['failed'] == 0) {
      _snack('Berhasil sinkron ${result['success']} transaksi');
    } else {
      _snack('Berhasil ${result['success']}, gagal ${result['failed']}. Error: $lastError');
    }
  }

  Future<void> _editTransaksi(Map<String, dynamic> trx) async {
    final items = (jsonDecode(trx['items_json']) as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final method = ValueNotifier<String>(trx['metode']?.toString() ?? 'Tunai');
    var saving = false;

    try {
      final updatedItems = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
          int total() => items.fold<int>(0, (sum, item) => sum + ((item['harga'] as num).toInt() * (item['qty'] as num).toInt()));
          return AlertDialog(
            title: Text('Edit Transaksi ${trx['id_transaksi']}'),
            content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['nama'].toString()),
                  subtitle: Text('${item['qty']} x ${_currencyFormat.format(item['harga'])}'),
                  trailing: SizedBox(width: 132, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    IconButton(onPressed: () => setDialogState(() { final qty = (item['qty'] as num).toInt(); if (qty > 1) { item['qty'] = qty - 1; } else { items.removeAt(index); } }), icon: const Icon(Icons.remove_circle_outline)),
                    Text('${item['qty']}'),
                    IconButton(onPressed: () => setDialogState(() => item['qty'] = (item['qty'] as num).toInt() + 1), icon: const Icon(Icons.add_circle_outline)),
                  ])),
                );
              }),
              const Divider(),
              Align(alignment: Alignment.centerRight, child: Text('Total: ${_currencyFormat.format(total())}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(valueListenable: method, builder: (context, value, _) => DropdownButtonFormField<String>(value: value.toLowerCase() == 'qris' ? 'QRIS' : (value.toLowerCase() == 'kris' ? 'QRIS' : 'Tunai'), decoration: const InputDecoration(labelText: 'Metode pembayaran'), items: const [DropdownMenuItem(value: 'Tunai', child: Text('Tunai')), DropdownMenuItem(value: 'QRIS', child: Text('QRIS'))], onChanged: (v) { if (v != null) method.value = v; })),
            ]))),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Batal')),
              ElevatedButton(onPressed: saving || items.isEmpty ? null : () async {
                setDialogState(() => saving = true);
                final prefs = await SharedPreferences.getInstance();
                final url = prefs.getString('url_appscript') ?? '';
                final branch = prefs.getString('nama_cabang') ?? '';
                final kasir = prefs.getString('nama_kasir') ?? '';
                final id = trx['id_transaksi'].toString();
                final normalizedMethod = method.value == 'Kris' ? 'QRIS' : method.value;
                final newTotal = total();
                final resultItems = items.map((item) => Map<String, dynamic>.from(item)).toList();
                final tanggal = trx['tanggal'].toString();
                final waktu = trx['waktu'].toString();

                // Update lokal dulu (offline-first).
                await DatabaseHelper.instance.editTransaksi({
                  'id_transaksi': id,
                  'tanggal': tanggal,
                  'waktu': waktu,
                  'total': newTotal,
                  'metode': normalizedMethod,
                  'items_json': jsonEncode(resultItems),
                  'status_sync': (trx['status_sync'] as num).toInt() == 1 ? 1 : 0,
                });

                final wasSynced = (trx['status_sync'] as num).toInt() == 1;
                if (wasSynced && url.isNotEmpty) {
                  final serverOk = await ApiService.editTransaksi(
                    url: url,
                    namaCabang: branch,
                    idTransaksi: id,
                    tanggal: tanggal,
                    waktu: waktu,
                    total: newTotal,
                    metode: normalizedMethod,
                  );
                  if (!serverOk) {
                    // Gagal kirim → enqueue agar SyncService retry nanti.
                    await DatabaseHelper.instance.enqueueSyncOperation(
                      id: id,
                      action: 'upsert',
                      payload: {
                        'action': 'simpanTransaksi',
                        'id_transaksi': id,
                        'nama_cabang': branch,
                        'nama_kasir': kasir,
                        'metode': normalizedMethod,
                        'tanggal': tanggal,
                        'waktu': waktu,
                        'items': resultItems,
                      },
                    );
                    await DatabaseHelper.instance.updateStatusSyncPending(id);
                  }
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext, resultItems);
              }, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan')),
            ],
          );
        }),
      );
      if (updatedItems == null || !mounted) return;
      await _loadRiwayat();
      _snack('Transaksi berhasil diperbarui');
    } finally {
      method.dispose();
    }
  }

  Future<void> _hapusTransaksi(Map<String, dynamic> trx) async {
    final id = trx['id_transaksi'].toString();
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Hapus transaksi?'),
      content: const Text('Transaksi akan dihapus dari aplikasi dan Google Sheets. Tindakan ini tidak dapat dibatalkan.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus'))],
    )) ?? false;
    if (!confirm) return;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final branch = prefs.getString('nama_cabang') ?? '';
    final wasSynced = (trx['status_sync'] as num).toInt() == 1;

    // Hapus lokal dulu.
    await DatabaseHelper.instance.hapusTransaksi(id);

    if (wasSynced && url.isNotEmpty) {
      final serverOk = await ApiService.hapusTransaksi(url: url, namaCabang: branch, idTransaksi: id);
      if (!serverOk) {
        // Gagal hapus di server → enqueue delete agar retry.
        await DatabaseHelper.instance.enqueueSyncOperation(
          id: id,
          action: 'delete',
          payload: {
            'action': 'hapusTransaksi',
            'id_transaksi': id,
            'nama_cabang': branch,
          },
        );
        _snack('Dihapus lokal. Sinkron hapus akan dicoba ulang otomatis.');
        await _loadRiwayat();
        return;
      }
    }

    await _loadRiwayat();
    _snack('Transaksi dihapus');
  }

  Widget _buildOmsetMetode(String label, int amount, IconData icon, Color color) => Row(children: [
    Icon(icon, size: 20, color: color), const SizedBox(width: 6), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12)), Text(_currencyFormat.format(amount), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: color))])),
  ]);

  Widget _buildTransactionCard(Map<String, dynamic> trx) {
    final status = (trx['status_sync'] as num).toInt();
    final isSynced = status == 1;
    final id = trx['id_transaksi'].toString();
    return Card(child: ListTile(
      leading: CircleAvatar(backgroundColor: isSynced ? Colors.green : Colors.orange, child: Icon(isSynced ? Icons.check : Icons.cloud_upload, color: Colors.white)),
      title: Text('ID: $id', style: const TextStyle(fontSize: 12)),
      subtitle: Text('${trx['tanggal']} | ${trx['waktu']}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(_currencyFormat.format(trx['total']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        PopupMenuButton<String>(tooltip: 'Aksi transaksi', onSelected: (action) { if (action == 'edit') _editTransaksi(trx); if (action == 'delete') _hapusTransaksi(trx); }, itemBuilder: (context) => const [PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit), title: Text('Edit'))), PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Hapus')))]),
      ]),
      onTap: () {
        final items = jsonDecode(trx['items_json']) as List<dynamic>;
        showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Detail Transaksi'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: items.length, itemBuilder: (context, i) { final item = Map<String, dynamic>.from(items[i] as Map); return Text('${item['qty']}x ${item['nama']} - ${_currencyFormat.format(item['harga'])}'); })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))]));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _transaksiTerfilter;
    const filters = ['Semua', 'Hari Ini', 'Bulan Ini', 'Custom'];
    final ranking = _peringkatProduk;
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Penjualan'), backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white, actions: [
        if (_sedangSinkron) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))) else ...[
          IconButton(icon: const Icon(Icons.cloud_sync), tooltip: 'Sinkron transaksi tertunda', onPressed: () => _sinkronSemua()),
          IconButton(icon: const Icon(Icons.sync), tooltip: 'Sinkronisasi paksa', onPressed: () => _sinkronSemua(paksa: true)),
        ],
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: filters.map((filter) { final active = _filterAktif == filter; return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(filter), selected: active, onSelected: (_) { setState(() => _filterAktif = filter); _loadRiwayat(); })); }).toList()))),
        Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(children: [const Icon(Icons.trending_up, color: Color(0xFFD32F2F)), const SizedBox(width: 10), const Expanded(child: Text('Total Omset')), Text(_currencyFormat.format(_totalOmset), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F), fontSize: 18))]),
          const Divider(),
          Row(children: [Expanded(child: _buildOmsetMetode('Tunai', _totalTunai, Icons.payments_outlined, Colors.green)), const SizedBox(width: 12), Expanded(child: _buildOmsetMetode('QRIS', _totalQris, Icons.qr_code_2, Colors.blue))]),
        ]))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: TextField(controller: _productSearchController, decoration: InputDecoration(labelText: 'Filter nama produk / produk terlaris', prefixIcon: const Icon(Icons.search), suffixIcon: _filterProduk.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _productSearchController.clear(); setState(() => _filterProduk = ''); }), border: const OutlineInputBorder()), onChanged: (value) => setState(() => _filterProduk = value.trim()))),
        if (ranking.isNotEmpty) SizedBox(height: 110, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: ranking.length, itemBuilder: (context, index) { final entry = ranking[index]; return SizedBox(width: 220, child: Card(child: ListTile(leading: CircleAvatar(child: Text('${index + 1}')), title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${entry.value['qty']} terjual'), trailing: Text(_currencyFormat.format(entry.value['nominal']))))); })),
        Expanded(child: transactions.isEmpty ? const Center(child: Text('Tidak ada riwayat transaksi')) : ListView.builder(padding: const EdgeInsets.all(8), itemCount: transactions.length, itemBuilder: (context, index) => _buildTransactionCard(transactions[index]))),
      ]),
    );
  }
}
