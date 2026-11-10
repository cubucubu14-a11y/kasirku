import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';

class PrinterService {
  // Fungsi untuk mencari printer Bluetooth yang sudah di-pairing
  static Future<List<BluetoothDevice>> getPrinters() async {
    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return bondedDevices;
    } catch (e) {
      return [];
    }
  }

  // Fungsi untuk mencetak struk
  static Future<bool> cetakStruk(BluetoothDevice printer, String cabang, String kasir, List<Map<String, dynamic>> items, int total) async {
    BluetoothConnection? connection;
    try {
      // 1. Hubungkan ke Printer
      connection = await BluetoothConnection.toAddress(printer.address);
      
      final now = DateTime.now();
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

      // Perintah ESC/POS untuk inisialisasi printer
      List<int> bytes = [27, 64]; 

      // 2. Susun teks struk
      String struk = "";
      struk += "        $cabang\n";
      struk += "--------------------------------\n";
      struk += "${formatter.format(now)}\n";
      struk += "Kasir: $kasir\n";
      struk += "--------------------------------\n";
      
      for (var item in items) {
        String nama = item['nama'];
        if (nama.length > 15) nama = nama.substring(0, 15);
        int qty = item['qty'];
        int harga = item['harga'] * qty;
        
        String qtyStr = qty.toString();
        String hargaStr = currency.format(harga);
        
        int spasi = 32 - (nama.length + qtyStr.length + hargaStr.length);
        if (spasi < 1) spasi = 1;
        
        struk += "$nama${' ' * spasi}$qtyStr$hargaStr\n";
      }
      
      struk += "--------------------------------\n";
      String totalStr = currency.format(total);
      int spasiTotal = 32 - (5 + totalStr.length);
      struk += "TOTAL:${' ' * spasiTotal}$totalStr\n";
      struk += "--------------------------------\n";
      struk += "      Terima Kasih :)\n\n\n\n";

      // 3. Kirim teks ke printer (diubah ke bytes)
      bytes.addAll(struk.codeUnits);
      
      // 4. Perintah potong kertas (jika printer support)
      bytes.addAll([27, 100, 4]); // Feed 4 lines
      // bytes.addAll([29, 86, 65, 0]); // Auto cut (buka komentar jika printer punya auto-cutter)

      // Eksekusi cetak
      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent;
      
      // 5. Tutup koneksi
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
