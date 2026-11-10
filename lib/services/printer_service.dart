import 'package:intl/intl.dart';

class PrinterService {
  // Fungsi simulasi cetak struk (menampilkan struk di layar)
  static Future<bool> cetakStruk(String cabang, String kasir, List<Map<String, dynamic>> items, int total) async {
    try {
      final now = DateTime.now();
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
      struk += "      Terima Kasih :)\n";

      // Simulasi print (kita cetak ke console / tidak error)
      print("=== STRUK KASIRKU ===");
      print(struk);
      print("=====================");
      
      return true;
    } catch (e) {
      return false;
    }
  }
}
