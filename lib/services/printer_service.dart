import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:intl/intl.dart';

class PrinterService {
  static final FlutterThermalPrinter _instance = FlutterThermalPrinter.instance;

  // Fungsi untuk mencari printer Bluetooth yang sudah di-pairing di HP
  static Future<List<Printer>> getPrinters() async {
    try {
      List<Printer> printers = await _instance.getPrinters();
      return printers.where((p) => p.connectionType == ConnectionType.bluetooth).toList();
    } catch (e) {
      return [];
    }
  }

  // Fungsi untuk mencetak struk
  static Future<bool> cetakStruk(Printer printer, String cabang, String kasir, List<Map<String, dynamic>> items, int total) async {
    try {
      final now = DateTime.now();
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

      // Format teks struk 58mm (32 karakter per baris)
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
        
        // Padding agar rata kanan
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

      // Perintah cetak
      await _instance.connect(printer);
      await _instance.printText(struk);
      await _instance.disconnect();
      
      return true;
    } catch (e) {
      return false;
    }
  }
}
