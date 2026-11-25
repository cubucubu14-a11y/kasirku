import 'dart:convert';
import 'dart:math';

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
  List<String> _zombieIds = [];
  String _filterAktif = 'Hari Ini';
  DateTime _selectedDate = DateTime.now();
  bool _sedangSinkron = false;
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
  }

  Future<void> _loadRiwayat() async {
    String? tanggalFilter;
    final formatter = DateFormat('yyyy-MM-dd');
    if (_filterAktif == 'Hari Ini') {
      tanggalFilter = formatter.format(_selectedDate);
    } else if (_filterAktif == 'Bulan Ini') {
      tanggalFilter = formatter.format(DateTime.now()).substring(0, 7);
    } else if (_filterAktif == 'Custom') {
      final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
      if (picked == null) return;
      _selectedDate = picked;
      tanggalFilter = formatter.format(picked);
    }

    final data = await DatabaseHelper.instance.getTransaksi(filterTanggal: tanggalFilter);
    if (!mounted) return;
    setState(() {
      _riwayat = data;
      _zombieIds = [];
    });

    if (tanggalFilter != null && tanggalFilter.length == 10) {
       final zombies = await SyncService.instance.cekDataZombie(filterTanggal: tanggalFilter);
       if (mounted) setState(() => _zombieIds = zombies);
    }
  }

  void _geserTanggal(int days) {
    setState(() {
      _filterAktif = 'Hari Ini';
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadRiwayat();
  }

  List<Map<String, dynamic>> get _transaksiAktif => _riwayat.where((t) => (t['status_sync'] as num).toInt() != 2).toList();
  int get _totalTransaksi => _transaksiAktif.length;
  int get _totalOmset => _transaksiAktif.fold<int>(0, (sum, t) => sum + (t['total'] as num).toInt());
  int get _totalTunai => _transaksiAktif.where((t) => (t['metode']?.toString().toLowerCase() ?? 'tunai') == 'tunai').fold<int>(0, (sum, t) => sum + (t['total'] as num).toInt());
  int get _totalQris => _transaksiAktif.where((t) { final method = t['metode']?.toString().toLowerCase() ?? ''; return method == 'qris' || method == 'kris'; }).fold<int>(0, (sum, t) => sum + (t['total'] as num).toInt());

  List<MapEntry<String, Map<String, int>>> get _peringkatProduk {
    final sales = <String, Map<String, int>>{};
    for (final trx in _transaksiAktif) {
      try {
        final items = jsonDecode(trx['items_json']) as List<dynamic>;
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final name = item['nama'].toString();
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

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sinkronSemua() async {
    if (_sedangSinkron) return;
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    if (url.isEmpty) { _snack('URL Apps Script belum diisi di menu Pengaturan'); return; }

    setState(() => _sedangSinkron = true);
    Map<String, int> result = {'success': 0, 'failed': 0};
    String lastError = '';
    try {
      result = await SyncService.instance.syncPending();
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

  Future<void> _paksaHijau() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paksa Sinkron (Hijau)?'),
        content: const Text('Fitur ini akan mengubah status semua transaksi Oranye menjadi Hijau. Gunakan HANYA jika kamu yakin data transaksi tersebut sudah masuk ke Google Sheets.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Paksa Hijau')),
        ],
      ),
    ) ?? false;
    if (!confirm) return;

    final db = await DatabaseHelper.instance.database;
    await db.update('transaksi', {'status_sync': 1}, where: 'status_sync = ?', whereArgs: [0]);
    await db.delete('sync_queue');
    
    await _loadRiwayat();
    _snack('Status transaksi berhasil dipaksa menjadi Hijau');
  }

  Future<void> _hapusZombie(String id) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Hapus Data Zombie?'),
      content: Text('Hapus transaksi $id dari Google Sheets secara permanen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus'))],
    )) ?? false;
    if (!confirm) return;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final branch = prefs.getString('nama_cabang') ?? '';
    final ok = await ApiService.hapusTransaksi(url: url, namaCabang: branch, idTransaksi: id);
    if (ok) { _snack('Data zombie dihapus dari Sheet'); _loadRiwayat(); } 
    else { _snack('Gagal menghapus: ${ApiService.lastError}'); }
  }

  Future<void> _tarikZombie(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final branch = prefs.getString('nama_cabang') ?? '';
    final data = await ApiService.tarikTransaksi(url, branch, id);
    if (data == null) { _snack('Gagal menarik data: ${ApiService.lastError}'); return; }

    String itemsJson = data['detail_produk']?.toString() ?? '[]';
    if (itemsJson == '' || !itemsJson.startsWith('[')) {
      itemsJson = jsonEncode([{'nama': 'Tarik dari Sheet', 'qty': 1, 'harga': data['total']}]);
    }

    await DatabaseHelper.instance.simpanTransaksi({
      'id_transaksi': data['id'], 'tanggal': data['tanggal'], 'waktu': data['waktu'],
      'total': data['total'], 'metode': data['metode'],
      'items_json': itemsJson, 
      'status_sync': 1,
    });
    _snack('Transaksi $id berhasil ditarik ke HP');
    _loadRiwayat();
  }

  void _showChartBottomSheet() {
    final ranking = _peringkatProduk;
    if (ranking.isEmpty) { _snack('Belum ada produk terjual.'); return; }
    final maxQty = ranking.first.value['qty']!.toDouble();

    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12, bottom: 8), height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('📊 Semua Produk Terjual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16), itemCount: ranking.length,
                itemBuilder: (context, index) {
                  final entry = ranking[index];
                  final qty = entry.value['qty']!;
                  final nominal = entry.value['nominal']!;
                  final percentage = max(5.0, (qty / maxQty) * 100);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Expanded(child: Text('${index + 1}. ${entry.key} (${qty}x)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(_currencyFormat.format(nominal), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                      ]),
                      const SizedBox(height: 6),
                      LayoutBuilder(builder: (context, constraints) {
                        return Stack(children: [
                          Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5))),
                          Container(height: 10, width: constraints.maxWidth * (percentage / 100), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFF44336)]), borderRadius: BorderRadius.circular(5))),
                        ]);
                      }),
                    ]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTransaksi(Map<String, dynamic> trx) async {
    final items = (jsonDecode(trx['items_json']) as List<dynamic>).map((item) => Map<String, dynamic>.from(item as Map)).toList();
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
                  contentPadding: EdgeInsets.zero, title: Text(item['nama'].toString()), subtitle: Text('${item['qty']} x ${_currencyFormat.format(item['harga'])}'),
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

                await DatabaseHelper.instance.editTransaksi({'id_transaksi': id, 'tanggal': tanggal, 'waktu': waktu, 'total': newTotal, 'metode': normalizedMethod, 'items_json': jsonEncode(resultItems), 'status_sync': (trx['status_sync'] as num).toInt() == 1 ? 1 : 0});
                final wasSynced = (trx['status_sync'] as num).toInt() == 1;
                if (wasSynced && url.isNotEmpty) {
                  final serverOk = await ApiService.editTransaksi(url: url, namaCabang: branch, idTransaksi: id, tanggal: tanggal, waktu: waktu, total: newTotal, metode: normalizedMethod, items: resultItems);
                  if (!serverOk) {
                    await DatabaseHelper.instance.enqueueSyncOperation(id: id, action: 'upsert', payload: {'action': 'simpanTransaksi', 'id_transaksi': id, 'nama_cabang': branch, 'nama_kasir': kasir, 'metode': normalizedMethod, 'tanggal': tanggal, 'waktu': waktu, 'items': resultItems});
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
      // PERBAIKAN BUG 1: Hapus method.dispose() yang bikin crash
      // method.dispose(); 
    }
  }

  Future<void> _hapusTransaksi(Map<String, dynamic> trx) async {
    final id = trx['id_transaksi'].toString();
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Hapus transaksi?'), content: const Text('Transaksi akan dihapus dari aplikasi dan Google Sheets.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus'))],
    )) ?? false;
    if (!confirm) return;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final branch = prefs.getString('nama_cabang') ?? '';

    await DatabaseHelper.instance.hapusTransaksi(id);
    if (url.isNotEmpty) {
      final serverOk = await ApiService.hapusTransaksi(url: url, namaCabang: branch, idTransaksi: id);
      if (!serverOk) {
        await DatabaseHelper.instance.enqueueSyncOperation(id: id, action: 'delete', payload: {'action': 'hapusTransaksi', 'id_transaksi': id, 'nama_cabang': branch});
        _snack('Dihapus lokal. Sinkron hapus akan dicoba ulang otomatis.'); await _loadRiwayat(); return;
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
    final isTunai = (trx['metode']?.toString().toLowerCase() ?? 'tunai') == 'tunai';
    
    String formattedDate = '';
    try {
      final date = DateTime.parse('${trx['tanggal']} ${trx['waktu']}');
      formattedDate = DateFormat('dd/MM • HH:mm').format(date);
    } catch (_) { formattedDate = '${trx['tanggal']} • ${trx['waktu']}'; }

    return Card(
      margin: const EdgeInsets.only(bottom: 8), elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          final items = jsonDecode(trx['items_json']) as List<dynamic>;
          showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Detail Transaksi'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: items.length, itemBuilder: (context, i) { final item = Map<String, dynamic>.from(items[i] as Map); return Text('${item['qty']}x ${item['nama']} - ${_currencyFormat.format(item['harga'])}'); })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))]));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_currencyFormat.format(trx['total']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(id, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              
              Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isSynced ? Icons.check_circle : Icons.cloud_upload, color: isSynced ? Colors.green : Colors.orange, size: 18),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isTunai ? Colors.green[100] : Colors.blue[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isTunai ? 'TUNAI' : 'QRIS',
                          style: TextStyle(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                            color: isTunai ? Colors.green[800] : Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(formattedDate, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                PopupMenuButton<String>(icon: const Icon(Icons.more_vert, color: Colors.grey), onSelected: (action) { if (action == 'edit') _editTransaksi(trx); if (action == 'delete') _hapusTransaksi(trx); }, itemBuilder: (context) => const [PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit), title: Text('Edit'))), PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Hapus')))]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ranking = _peringkatProduk;
    final topProduct = ranking.isNotEmpty ? ranking.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'), backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white,
        actions: [
          if (_sedangSinkron) 
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else ...[
            IconButton(icon: const Icon(Icons.cloud_sync), tooltip: 'Sinkron transaksi', onPressed: _sinkronSemua),
            PopupMenuButton<String>(
              onSelected: (value) { if (value == 'paksa_hijau') _paksaHijau(); },
              itemBuilder: (context) => [const PopupMenuItem(value: 'paksa_hijau', child: Text('Paksa Sinkron (Hijau)'))],
            ),
          ]
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _geserTanggal(-1),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Hari Ini', style: TextStyle(fontSize: 12)),
                        selected: _filterAktif == 'Hari Ini',
                        onSelected: (_) { setState(() { _filterAktif = 'Hari Ini'; _selectedDate = DateTime.now(); }); _loadRiwayat(); },
                      ),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Text('Bulan Ini', style: TextStyle(fontSize: 12)),
                        selected: _filterAktif == 'Bulan Ini',
                        onSelected: (_) { setState(() => _filterAktif = 'Bulan Ini'); _loadRiwayat(); },
                      ),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Text('Custom', style: TextStyle(fontSize: 12)),
                        selected: _filterAktif == 'Custom',
                        onSelected: (_) { setState(() => _filterAktif = 'Custom'); _loadRiwayat(); },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _geserTanggal(1),
                ),
              ],
            ),
          ),
          
          if (_filterAktif == 'Hari Ini')
            Text('Tanggal: ${DateFormat('dd MMM yyyy').format(_selectedDate)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),

          if (_zombieIds.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red[50], border: Border.all(color: Colors.red), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red), const SizedBox(width: 8),
                  Expanded(child: Text('Terdapat ${_zombieIds.length} data di Sheet tapi tidak ada di HP.', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 8),
                ..._zombieIds.take(3).map((id) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(child: Text(id, style: const TextStyle(fontSize: 11, color: Colors.black87))),
                    TextButton(onPressed: () => _hapusZombie(id), child: const Text('Hapus', style: TextStyle(fontSize: 11))),
                    TextButton(onPressed: () => _tarikZombie(id), child: const Text('Tarik', style: TextStyle(fontSize: 11))),
                  ]),
                )),
                if (_zombieIds.length > 3) Text('+ ${_zombieIds.length - 3} data lainnya...', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ]),
            ),

          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.trending_up, color: Color(0xFFD32F2F)), const SizedBox(width: 10),
                  const Expanded(child: Text('Total Omset')),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)), child: Text('$_totalTransaksi Transaksi', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))),
                ]),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: Text(_currencyFormat.format(_totalOmset), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F), fontSize: 22))),
                const Divider(height: 24),
                Row(children: [
                  Expanded(child: _buildOmsetMetode('Tunai', _totalTunai, Icons.payments_outlined, Colors.green)), const SizedBox(width: 12),
                  Expanded(child: _buildOmsetMetode('QRIS', _totalQris, Icons.qr_code_2, Colors.blue)),
                ]),
              ]),
            ),
          ),

          if (topProduct != null)
            GestureDetector(
              onTap: _showChartBottomSheet,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFFFF8E1), border: Border.all(color: const Color(0xFFFFE082)), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Text('🏆 Terlaris: ${topProduct.key} (${topProduct.value['qty']} terjual)', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFF57F17)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const Text('📊 Grafik >', style: TextStyle(color: Color(0xFFF57F17), fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
              ),
            ),

          Expanded(
            child: _transaksiAktif.isEmpty
                ? const Center(child: Text('Tidak ada riwayat transaksi'))
                : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), itemCount: _transaksiAktif.length, itemBuilder: (context, index) => _buildTransactionCard(_transaksiAktif[index])),
          ),
        ],
      ),
    );
  }
}
