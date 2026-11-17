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
  final TextEditingController _productSearchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  bool _sedangSinkron = false;

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

  int get _totalOmset {
    return _riwayat
        .where((trx) => (trx['status_sync'] as num).toInt() != 2)
        .fold<int>(
          0,
          (sum, trx) => sum + (trx['total'] as num).toInt(),
        );
  }

  List<MapEntry<String, Map<String, int>>> get _peringkatProduk {
    final sales = <String, Map<String, int>>{};

    for (final trx in _riwayat) {
      if ((trx['status_sync'] as num).toInt() == 2) continue;

      try {
        final items = jsonDecode(trx['items_json']) as List<dynamic>;
        for (final rawItem in items) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          final nama = item['nama'].toString();
          if (_filterProduk.isNotEmpty &&
              !nama.toLowerCase().contains(_filterProduk.toLowerCase())) {
            continue;
          }

          final qty = (item['qty'] as num).toInt();
          final harga = (item['harga'] as num).toInt();
          final totals = sales.putIfAbsent(
            nama,
            () => <String, int>{'qty': 0, 'nominal': 0},
          );
          totals['qty'] = totals['qty']! + qty;
          totals['nominal'] = totals['nominal']! + (harga * qty);
        }
      } catch (_) {
        // Abaikan detail transaksi yang rusak, agar data riwayat lainnya tampil.
      }
    }

    final entries = sales.entries.toList();
    entries.sort((a, b) {
      final qtyComparison = b.value['qty']!.compareTo(a.value['qty']!);
      if (qtyComparison != 0) return qtyComparison;
      return b.value['nominal']!.compareTo(a.value['nominal']!);
    });
    return entries;
  }

  bool _containsFilteredProduct(Map<String, dynamic> trx) {
    if (_filterProduk.isEmpty) return true;
    try {
      final items = jsonDecode(trx['items_json']) as List<dynamic>;
      return items.any(
        (item) => item['nama']
            .toString()
            .toLowerCase()
            .contains(_filterProduk.toLowerCase()),
      );
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

  Future<void> _sinkronSemua() async {
    if (_sedangSinkron) return;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url_appscript') ?? '';
    final cabang = prefs.getString('nama_cabang') ?? '';
    final kasir = prefs.getString('nama_kasir') ?? '';

    if (url.isEmpty) {
      _snack('URL Apps Script belum diisi di menu Pengaturan');
      return;
    }

    final pending = await DatabaseHelper.instance.getTransaksiBelumSync();
    if (pending.isEmpty) {
      _snack('Semua transaksi sudah tersinkron');
      return;
    }

    setState(() => _sedangSinkron = true);
    var berhasil = 0;
    var gagal = 0;
    var errorTerakhir = '';

    for (final trx in pending) {
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

    if (!mounted) return;
    setState(() => _sedangSinkron = false);
    await _loadRiwayat();
    _snack(
      gagal == 0
          ? 'Berhasil sinkron $berhasil transaksi'
          : 'Berhasil $berhasil, gagal $gagal. Error: $errorTerakhir',
    );
  }

  Future<void> _prosesVoid(String idTrx, String statusSync) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Batalkan Transaksi?'),
            content: const Text(
              'Transaksi ini akan ditandai sebagai VOID dan tidak bisa dikembalikan.',
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

    var suksesServer = true;
    if (statusSync == '1') {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('url_appscript') ?? '';
      final cabang = prefs.getString('nama_cabang') ?? '';
      if (url.isNotEmpty) {
        suksesServer = await ApiService.voidTransaksi(url, cabang, idTrx);
      } else {
        suksesServer = false;
        ApiService.lastError = 'URL Apps Script belum diisi';
      }
    }

    if (!suksesServer) {
      _snack(
        ApiService.lastError.isNotEmpty
            ? 'VOID gagal dikirim ke server: ${ApiService.lastError}'
            : 'VOID gagal dikirim ke server. Coba lagi nanti.',
      );
      return;
    }

    await DatabaseHelper.instance.voidTransaksiLokal(idTrx);
    await _loadRiwayat();
  }

  Widget _buildFilterTanggal() {
    const filters = ['Semua', 'Hari Ini', 'Bulan Ini', 'Custom'];
    return Padding(
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
                selectedColor: const Color(0xFFFFF0F0),
                labelStyle: TextStyle(
                  color: active ? const Color(0xFFD32F2F) : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPeringkatProduk() {
    final ranking = _peringkatProduk;
    if (ranking.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 116,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: ranking.length,
        itemBuilder: (context, index) {
          final entry = ranking[index];
          return SizedBox(
            width: 230,
            child: Card(
              color: index == 0 ? const Color(0xFFFFF0F0) : null,
              child: ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(
                  entry.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${entry.value['qty']} terjual'),
                trailing: Text(
                  _currencyFormat.format(entry.value['nominal']),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> trx) {
    final status = (trx['status_sync'] as num).toInt();
    final isVoid = status == 2;
    final isSynced = status == 1;
    final idTrx = trx['id_transaksi'].toString();

    return Card(
      color: isVoid ? Colors.grey[300] : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isVoid
              ? Colors.grey
              : (isSynced ? Colors.green : Colors.orange),
          child: Icon(
            isVoid
                ? Icons.cancel
                : (isSynced ? Icons.check : Icons.cloud_upload),
            color: Colors.white,
          ),
        ),
        title: Text(
          'ID: $idTrx',
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
                onPressed: () => _prosesVoid(idTrx, status.toString()),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Penjualan'),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          _sedangSinkron
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.cloud_sync),
                  tooltip: 'Sinkron ke Google Sheets',
                  onPressed: _sinkronSemua,
                ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterTanggal(),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.trending_up, color: Color(0xFFD32F2F)),
              title: const Text('Total Omset'),
              trailing: Text(
                _currencyFormat.format(_totalOmset),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextField(
              controller: _productSearchController,
              decoration: InputDecoration(
                labelText: 'Filter nama produk / lihat produk terlaris',
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
          _buildPeringkatProduk(),
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
