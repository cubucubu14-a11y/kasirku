import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class PrinterService {
  static Future<List<BluetoothDevice>> getPrinters() async {
    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return bondedDevices;
    } catch (e) {
      return [];
    }
  }

  static Future<bool> cetakStruk(BluetoothDevice printer, String cabang, String kasir, String idTrx, List<Map<String, dynamic>> items, int total, int bayar, int kembali, String metode) async {
    BluetoothConnection? connection;
    try {
      connection = await BluetoothConnection.toAddress(printer.address);
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      
      List<int> bytes = [];
      final now = DateTime.now();
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

      // Header
      bytes += generator.text(cabang, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.hr();
      
      // Info Transaksi
      bytes += generator.text('No: $idTrx', styles: const PosStyles(align: PosAlign.left));
      bytes += generator.text('Tgl: ${formatter.format(now)}', styles: const PosStyles(align: PosAlign.left));
      bytes += generator.text('Kasir: $kasir', styles: const PosStyles(align: PosAlign.left));
      bytes += generator.hr();

      // List Item
      for (var item in items) {
        String nama = item['nama'];
        int qty = item['qty'];
        int harga = item['harga'] * qty;
        
        bytes += generator.text(nama, styles: const PosStyles(align: PosAlign.left));
        bytes += generator.row([
          PosColumn(text: '  $qty x ${currency.format(item['harga'])}', width: 6, styles: const PosStyles(align: PosAlign.left)),
          PosColumn(text: currency.format(harga), width: 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      
      bytes += generator.hr();

      // Total & Pembayaran
      bytes += generator.row([
        PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(align: PosAlign.left, bold: true)),
        PosColumn(text: currency.format(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      bytes += generator.row([
        PosColumn(text: metode.toUpperCase(), width: 6, styles: const PosStyles(align: PosAlign.left)),
        PosColumn(text: currency.format(bayar), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
      if (metode == 'Tunai') {
        bytes += generator.row([
          PosColumn(text: 'KEMBALI', width: 6, styles: const PosStyles(align: PosAlign.left)),
          PosColumn(text: currency.format(kembali), width: 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      
      bytes += generator.hr();
      bytes += generator.text('Terima Kasih :)', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent;
      await connection.close();
      return true;
    } catch (e) {
      if (connection != null) await connection.close();
      return false;
    }
  }
}
