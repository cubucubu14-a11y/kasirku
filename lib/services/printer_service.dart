import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';

class PrinterService {
  // Fungsi untuk mencari printer Bluetooth yang sudah di-pairing
  static Future<List<BluetoothDevice>> getPrinters() async {
    try {
      // Ambil perangkat yang sudah di-pairing
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return bondedDevices;
    } catch (e) {
      return [];
    }
  }

  // Fungsi untuk mencetak struk menggunakan EscPosUtils
  static Future<bool> cetakStruk(BluetoothDevice printer, String cabang, String kasir, List<Map<String, dynamic>> items, int total) async {
    BluetoothConnection? connection;
    try {
      // 1. Hubungkan ke Printer
      connection = await BluetoothConnection.toAddress(printer.address);
      
      // 2. Inisialisasi Profile Printer 58mm
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      
      List<int> bytes = [];

      // 3. Cetak Header
      bytes += generator.text(cabang, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.hr();
      
      final now = DateTime.now();
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      bytes += generator.text(formatter.format(now), styles: const PosStyles(align: PosAlign.left));
      bytes += generator.text('Kasir: $kasir', styles: const PosStyles(align: PosAlign.left));
      bytes += generator.hr();

      // 4. Cetak Daftar Item
      final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
      for (var item in items) {
        String nama = item['nama'];
        int qty = item['qty'];
        int harga = item['harga'] * qty;
        
        // Baris 1: Nama Produk
        bytes += generator.text(nama, styles: const PosStyles(align: PosAlign.left));
        
        // Baris 2: Qty x Harga (Rata Kanan Kiri)
        bytes += generator.row([
          PosColumn(text: '  $qty x ${currency.format(item['harga'])}', width: 6, styles: const PosStyles(align: PosAlign.left)),
          PosColumn(text: currency.format(harga), width: 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      
      bytes += generator.hr();

      // 5. Cetak Total
      bytes += generator.row([
        PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(align: PosAlign.left, bold: true)),
        PosColumn(text: currency.format(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      
      bytes += generator.hr();
      bytes += generator.text('Terima Kasih :)', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      // 6. Kirim perintah ke Printer
      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent;
      
      // 7. Tutup koneksi
      await connection.close();
      connection = null;
      
      return true;
    } catch (e) {
      print("Error cetak bluetooth: $e");
      if (connection != null) {
        await connection.close();
      }
      return false;
    }
  }
}
