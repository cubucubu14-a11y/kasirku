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
  String _filterProduk = '';
  final _productSearchController = TextEditingController();
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

  int get _totalOmset => _riwayat.where((trx) => (trx['status_sync'] as int) != 2).fold<int>(0, (sum, trx) => sum + (trx['total'] as int));

  List<MapEntry<String, Map<String, int>>> get _peringkatProduk {
    final sales = <String, Map<String, int>>{};
    for (final trx in _riwayat) {
      if ((trx['status_sync'] as int) == 2) continue;
      try {
        final items = jsonDecode(trx['items_json']) as List;
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          final nama = item['nama'].toString();
          if (_filterProduk.isNotEmpty && !nama.toLowerCase().contains(_filterProduk.toLowerCase())) continue;
          final qty = (item['qty'] as num).toInt();
          final harga = (item['harga'] as num).toInt();
          final current = sales.putIfAbsent(nama, () => {'qty': 0, 'nominal': 0});
          current['qty'] = current['qty']! + qty;
          current['nominal'] = current['nominal']! + (harga * qty);
        }
      } catch (_) {
        // Abaikan detail transaksi yang rusak agar riwayat lain tetap tampil.
      }
    }
    final entries = sales.entries.toList();
    entries.sort((a, b) {
      final byQty = b.value['qty']!.compareTo(a.value['qty']!);
      return byQty != 0 ? byQty : b.value['nominal']!.compareTo(a.value['nominal']!);
    });
    return entries;
  }

  bool _containsFilteredProduct(Map<String, dynamic> trx) {
    if (_filterProduk.isEmpty) return true;
    try {
      final items = jsonDecode(trx['items_json']) as List;
      return items.any((item) => item['nama'].toString().toLowerCase().contains(_filterProduk.toLowerCase()));
    } catch (_) { return false; }
  }

  bool _sedangSinkron = false;
  void _snack(String pesan) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan))); }

  Future<void> _sinkronSemua() async {
    if (_sedangSinkron) return;
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final cabang = prefs.getString('nama_cabang') ?? '';
    final kasir = prefs.getString('nama_kasir') ?? '';
    if (url.isEmpty) { _snack('URL Apps Script belum diisi di menu Pengaturan'); return; }
    final pending = await DatabaseHelper.instance.getTransaksiBelumSync();
    if (pending.isEmpty) { _snack('Semua transaksi sudah tersinkron'); return; }
    setState(() => _sedangSinkron = true);
    int berhasil = 0, gagal = 0;
    String errorTerakhir = '';
    for (final trx in pending) {
      try {
        final List decoded = jsonDecode(trx['items_json']);
        final items = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        final sukses = await ApiService.kirimTransaksi(url, cabang, kasir, items, trx['metode']?.toString(), idTransaksi: trx['id_transaksi'].toString(), tanggal: trx['tanggal'].toString(), waktu: trx['waktu'].toString());
        if (sukses) { await DatabaseHelper.instance.updateStatusSync(trx['id_transaksi'].toString()); berhasil++; }
        else { gagal++; errorTerakhir = ApiService.lastError; }
      } catch (e) { gagal++; errorTerakhir = e.toString(); }
    }
    if (!mounted) return;
    setState(() => _sedangSinkron = false);
    await _loadRiwayat();
    _snack(gagal == 0 ? 'Berhasil sinkron $berhasil transaksi' : 'Berhasil $berhasil, gagal $gagal. Error: $errorTerakhir');
  }

  Future<void> _prosesVoid(String idTrx, String statusSync) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Batalkan Transaksi?'),
      content: const Text('Transaksi ini akan ditandai sebagai VOID dan tidak bisa dikembalikan.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('VOID'))],
    )) ?? false;
    if (!confirm) return;
    bool suksesServer = true;
    if (statusSync == '1') {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('url_appscript') ?? '';
      final cabang = prefs.getString('nama_cabang') ?? '';
      if (url.isNotEmpty) suksesServer = await ApiService.voidTransaksi(url, cabang, idTrx);
      else { suksesServer = false; ApiService.lastError = 'URL Apps Script belum diisi'; }
    }
    if (!suksesServer) { _snack(ApiService.lastError.isNotEmpty ? 'VOID gagal dikirim ke server: ${ApiService.lastError}' : 'VOID gagal dikirim ke server. Coba lagi nanti.'); return; }
    await DatabaseHelper.instance.voidTransaksiLokal(idTrx);
    await _loadRiwayat();
  }

  @override
  Widget build(BuildContext context) {
    final ranking = _peringkatProduk;
    final transactions = _riwayat.where(_containsFilteredProduct).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Penjualan'), backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white, actions: [
        _sedangSinkron ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))) : IconButton(icon: const Icon(Icons.cloud_sync), tooltip: 'Sinkron ke Google Sheets', onPressed: _sinkronSemua),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ['Semua', 'Hari Ini', 'Bulan Ini', 'Custom'].map((filter) {
          final active = _filterAktif == filter;
          return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(filter), selected: active, onSelected: (_) { setState(() => _filterAktif = filter); _loadRiwayat(); }, selectedColor: const Color(0xFFFFF0F0), labelStyle: TextStyle(color: active ? const Color(0xFFD32F2F) : Colors.black87, fontWeight: FontWeight.bold)));
        }).toList()))),
        Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(leading: const Icon(Icons.trending_up, color: Color(0xFFD32F2F)), title: const Text('Total Omset'), trailing: Text(_currencyFormat.format(_totalOmset), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))))),
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: TextField(controller: _productSearchController, decoration: InputDecoration(labelText: 'Filter nama produk / lihat produk terlaris', prefixIcon: const Icon(Icons.search), suffixIcon: _filterProduk.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _productSearchController.clear(); setState(() => _filterProduk = ''); }), border: const OutlineInputBorder()), onChanged: (value) => setState(() => _filterProduk = value.trim()))),
        if (ranking.isNotEmpty) SizedBox(height: 116, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), itemCount: ranking.length, itemBuilder: (context, index) {
          final entry = ranking[index];
          return SizedBox(width: 230, child: Card(color: index == 0 ? const Color(0xFFFFF0F0) : null, child: ListTile(leading: CircleAvatar(child: Text('${index + 1}')), title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${entry.value['qty']} terjual'), trailing: Text(_currencyFormat.format(entry.value['nominal']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))));
        })),
        Expanded(child: transactions.isEmpty ? const Center(child: Text('Tidak ada riwayat transaksi')) : ListView.builder(padding: const EdgeInsets.all(8), itemCount: transactions.length, itemBuilder: (context, index) {
          final trx = transactions[index];
          final status = trx['status_sync'] as int;
          final isVoid = status == 2;
          final isSynced = status == 1;
          return Card(color: isVoid ? Colors.grey[300] : Colors.white, child: ListTile(
            leading: CircleAvatar(backgroundColor: isVoid ? Colors.grey : (isSynced ? Colors.green : Colors.orange), child: Icon(isVoid ? Icons.cancel : (isSynced ? Icons.check : Icons.cloud_upload), color: Colors.white)),
            title: Text('ID: ${trx['id_transaksi']}', style: TextStyle(fontSize: 12, decoration: isVoid ? TextDecoration.lineThrough : null)),
            subtitle: Text('${trx['tanggal']} | ${trx['waktu']}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(isVoid ? 'VOID' : _currencyFormat.format(trx['total']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isVoid ? Colors.red : Colors.black)), if (!isVoid) IconButton(icon: const Icon(Icons.block, color: Colors.red), tooltip: 'Void Transaksi', onPressed: () => _prosesVoid(trx['id_transaksi'].toString(), status.toString()))]),
            onTap: () {
              final List items = jsonDecode(trx['items_json']);
              showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Detail Transaksi'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: items.length, itemBuilder: (context, i) { final item = items[i]; return Text('${item['qty']}x ${item['nama']} - ${_currencyFormat.format(item['harga'])}'); })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))]);
            },
          ));
        })),
      ]),
    );
  }
}
