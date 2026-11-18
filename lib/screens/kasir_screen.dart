import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../services/printer_service.dart';

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  String _namaKasir = '';
  String _namaCabang = '';
  String _urlAppScript = '';
  List<Map<String, dynamic>> _produkList = [];
  final List<Map<String, dynamic>> _keranjang = [];
  String _kategoriAktif = 'Semua';
  BluetoothDevice? _selectedPrinter;
  bool _isLoading = false;

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Refresh data saat kembali ke tab Kasir (misal setelah ubah produk di Pengaturan).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final produk = await DatabaseHelper.instance.getProduk();
    final printerAddress = prefs.getString('printer_address');
    BluetoothDevice? printer;
    if (printerAddress != null) {
      final printers = await PrinterService.getPrinters();
      for (final item in printers) {
        if (item.address == printerAddress) {
          printer = item;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _namaKasir = prefs.getString('nama_kasir') ?? '';
      _namaCabang = prefs.getString('nama_cabang') ?? '';
      _urlAppScript = prefs.getString('url_appscript') ?? '';
      _produkList = produk;
      _selectedPrinter = printer;
    });
  }

  void _tambahKeKeranjang(Map<String, dynamic> produk) {
    setState(() {
      final index = _keranjang.indexWhere((item) => item['id'] == produk['id']);
      if (index != -1) {
        _keranjang[index]['qty']++;
      } else {
        _keranjang.add({'id': produk['id'], 'nama': produk['nama'], 'harga': produk['harga'], 'qty': 1});
      }
    });
  }

  void _kurangiKeranjang(int index) {
    setState(() {
      if (_keranjang[index]['qty'] > 1) {
        _keranjang[index]['qty']--;
      } else {
        _keranjang.removeAt(index);
      }
    });
  }

  int get _totalBelanja => _keranjang.fold<int>(0, (total, item) => total + (item['harga'] as int) * (item['qty'] as int));

  Future<void> _pilihPrinter() async {
    final printers = await PrinterService.getPrinters();
    if (!mounted) return;
    if (printers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada printer paired. Pair printer di pengaturan Bluetooth HP terlebih dahulu.')));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pilih Printer Bluetooth'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: printers.map((printer) => ListTile(
              title: Text(printer.name ?? 'Printer'),
              subtitle: Text(printer.address),
              trailing: _selectedPrinter?.address == printer.address ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('printer_address', printer.address);
                await prefs.setString('printer_name', printer.name ?? 'Printer');
                if (!mounted) return;
                setState(() => _selectedPrinter = printer);
                Navigator.pop(dialogContext);
              },
            )).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _bukaKeranjang() async {
    if (_keranjang.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Keranjang Belanja', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _keranjang.length,
                    itemBuilder: (context, index) {
                      final item = _keranjang[index];
                      return Card(
                        elevation: 0,
                        color: Colors.grey[100],
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white, child: Text(item['qty'].toString())),
                          title: Text(item['nama']),
                          subtitle: Text(_currencyFormat.format(item['harga'] * item['qty'])),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.remove_circle, color: Colors.orange), onPressed: () { setModalState(() => _kurangiKeranjang(index)); setState(() {}); }),
                              IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () { setModalState(() => _tambahKeKeranjang(item)); setState(() {}); }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_currencyFormat.format(_totalBelanja), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: () async {
                        final batal = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Batalkan pesanan?'),
                            content: const Text('Semua barang di keranjang akan dihapus.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, batalkan')),
                            ],
                          ),
                        );
                        if (batal == true) {
                          setState(() => _keranjang.clear());
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Batal'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showPembayaranDialog();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
                      child: const Text('PROSES BAYAR'),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPembayaranDialog() {
    String metode = 'Tunai';
    final bayarC = TextEditingController();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bayar = int.tryParse(bayarC.text) ?? 0;
          final kembali = (bayar - _totalBelanja).clamp(0, 1 << 31);
          void setNominal(int value) {
            bayarC.text = value.toString();
            setDialogState(() {});
          }

          return AlertDialog(
            title: const Text('Pembayaran'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total: ${_currencyFormat.format(_totalBelanja)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(label: const Text('Tunai'), selected: metode == 'Tunai', onSelected: (_) => setDialogState(() => metode = 'Tunai')),
                    ChoiceChip(label: const Text('QRIS'), selected: metode == 'QRIS', onSelected: (_) => setDialogState(() => metode = 'QRIS')),
                  ]),
                  const SizedBox(height: 12),
                  if (metode == 'Tunai') ...[
                    TextField(controller: bayarC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Uang Diterima', border: OutlineInputBorder()), onChanged: (_) => setDialogState(() {})),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      ActionChip(label: const Text('Uang Pas'), onPressed: () => setNominal(_totalBelanja)),
                      for (final value in [20000, 50000, 100000]) ActionChip(label: Text(_currencyFormat.format(value)), onPressed: () => setNominal(value)),
                    ]),
                    const SizedBox(height: 8),
                    Text('Kembalian: ${_currencyFormat.format(kembali)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ] else
                    const Text('Pembayaran via QRIS diasumsikan uang pas.', style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Kembali')),
              ElevatedButton(
                onPressed: _isLoading ? null : () {
                  final uangBayar = metode == 'Tunai' ? (int.tryParse(bayarC.text) ?? 0) : _totalBelanja;
                  if (metode == 'Tunai' && uangBayar < _totalBelanja) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uang kurang!')));
                    return;
                  }
                  Navigator.pop(dialogContext);
                  _previewStruk(metode, uangBayar, (uangBayar - _totalBelanja).clamp(0, 1 << 31));
                },
                child: const Text('SELESAI'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(bayarC.dispose);
  }

  Future<void> _previewStruk(String metode, int bayar, int kembali) async {
    final now = DateTime.now();
    final idTrx = 'TRX-${now.millisecondsSinceEpoch}';
    final shouldComplete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preview Struk'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_namaCabang, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Divider(),
              Text('No: $idTrx'),
              Text('Tanggal: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}'),
              Text('Kasir: $_namaKasir'),
              const Divider(),
              ..._keranjang.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['nama'].toString()),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${item['qty']} x ${_currencyFormat.format(item['harga'])}'),
                    Text(_currencyFormat.format(item['harga'] * item['qty'])),
                  ]),
                ]),
              )),
              const Divider(),
              _receiptRow('TOTAL', _currencyFormat.format(_totalBelanja), bold: true),
              _receiptRow(metode.toUpperCase(), _currencyFormat.format(bayar)),
              if (metode == 'Tunai') _receiptRow('KEMBALI', _currencyFormat.format(kembali)),
              const Divider(),
              const Text('Terima Kasih :)', textAlign: TextAlign.center),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Kembali')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(_selectedPrinter == null ? Icons.check : Icons.print),
            label: Text(_selectedPrinter == null ? 'Simpan Transaksi' : 'Simpan & Cetak'),
          ),
        ],
      ),
    );
    if (shouldComplete == true) await _prosesBayar(metode, bayar, kembali, now, idTrx);
  }

  Widget _receiptRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    ]),
  );

  Future<void> _prosesBayar(String metode, int bayar, int kembali, DateTime now, String idTrx) async {
    setState(() => _isLoading = true);
    try {
      final tanggal = DateFormat('yyyy-MM-dd').format(now);
      final waktu = DateFormat('HH:mm:ss').format(now);

      // Selalu simpan lokal + enqueue ke outbox agar tahan offline / crash.
      await DatabaseHelper.instance.simpanTransaksiOffline(
        {
          'id_transaksi': idTrx,
          'tanggal': tanggal,
          'waktu': waktu,
          'total': _totalBelanja,
          'metode': metode,
          'items_json': jsonEncode(_keranjang),
          'status_sync': 0,
        },
        {
          'action': 'simpanTransaksi',
          'id_transaksi': idTrx,
          'nama_cabang': _namaCabang,
          'nama_kasir': _namaKasir,
          'metode': metode,
          'tanggal': tanggal,
          'waktu': waktu,
          'items': _keranjang
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
        },
      );

      // Coba kirim langsung jika online. Kalau gagal, SyncService akan retry.
      if (_urlAppScript.isNotEmpty) {
        final sukses = await ApiService.kirimTransaksi(
          _urlAppScript,
          _namaCabang,
          _namaKasir,
          _keranjang,
          metode,
          idTransaksi: idTrx,
          tanggal: tanggal,
          waktu: waktu,
        );
        if (sukses) {
          // Hapus operasi dari outbox + tandai transaksi sudah sync.
          final pending = await DatabaseHelper.instance.getPendingSyncOperations();
          for (final op in pending) {
            if (op['transaction_id'].toString() == idTrx) {
              await DatabaseHelper.instance.completeSyncOperation(
                (op['id'] as num).toInt(),
                idTrx,
                op['action'].toString(),
              );
              break;
            }
          }
        }
      }

      if (_selectedPrinter != null) {
        final tercetak = await PrinterService.cetakStruk(_selectedPrinter!, _namaCabang, _namaKasir, idTrx, _keranjang, _totalBelanja, bayar, kembali, metode);
        if (!tercetak && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaksi tersimpan, tetapi struk gagal dicetak. Periksa koneksi printer.')));
      }
      if (!mounted) return;
      setState(() => _keranjang.clear());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan transaksi: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final produkTampil = _produkList.where((p) => _kategoriAktif == 'Semua' || p['kategori'] == _kategoriAktif).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Kasir: $_namaCabang', style: const TextStyle(fontSize: 16)), Text('Petugas: $_namaKasir', style: const TextStyle(fontSize: 12))]),
        backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.print), onPressed: _pilihPrinter, tooltip: _selectedPrinter == null ? 'Pilih Printer' : 'Printer: ${_selectedPrinter!.name ?? _selectedPrinter!.address}')],
      ),
      body: Column(children: [
        Container(height: 60, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: ListView(scrollDirection: Axis.horizontal, children: ['Semua', 'Makanan', 'Minuman'].map((kat) {
          final active = _kategoriAktif == kat;
          return Padding(padding: const EdgeInsets.only(right: 12), child: ChoiceChip(label: Text(kat), selected: active, onSelected: (_) => setState(() => _kategoriAktif = kat), selectedColor: const Color(0xFFFFF0F0), labelStyle: TextStyle(color: active ? const Color(0xFFD32F2F) : Colors.black87, fontWeight: FontWeight.bold)));
        }).toList())),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.1, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: produkTampil.length,
          itemBuilder: (context, index) {
            final produk = produkTampil[index];
            return InkWell(
              onTap: () => _tambahKeKeranjang(produk),
              borderRadius: BorderRadius.circular(12),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // --- BAGIAN GAMBAR YANG DIPERBAIKI ---
                      if (produk['gambar'] != null && produk['gambar'] != '')
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(produk['gambar']),
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 50), 

                      // --- TEKS & HARGA ---
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            produk['nama'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _currencyFormat.format(produk['harga']),
                                style: const TextStyle(
                                  color: Color(0xFFD32F2F),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Icon(Icons.add_circle, color: Color(0xFFD32F2F), size: 20),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        )),
      ]),
      floatingActionButton: _keranjang.isNotEmpty ? FloatingActionButton.extended(onPressed: _bukaKeranjang, backgroundColor: const Color(0xFFD32F2F), icon: const Icon(Icons.shopping_cart), label: Text('${_keranjang.length} Item - ${_currencyFormat.format(_totalBelanja)}')) : null,
    );
  }
}
