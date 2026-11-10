import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 1. Fungsi untuk mendaftarkan cabang baru ke Apps Script (buat tab sheet)
  static Future<bool> setupCabang(String url, String namaCabang) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "setupCabang",
          "namaCabang": namaCabang,
        }),
      );
      final data = jsonDecode(response.body);
      return data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // 2. Fungsi untuk mengirim transaksi ke Apps Script
  static Future<bool> kirimTransaksi(String url, String namaCabang, String kasir, List<Map<String, dynamic>> items) async {
    try {
      final now = DateTime.now();
      final tanggal = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final waktu = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      
      // Buat ID Transaksi unik (Timestamp + Random)
      final idTrx = "TRX-${now.millisecondsSinceEpoch}";

      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "simpanTransaksi",
          "id_transaksi": idTrx,
          "nama_cabang": namaCabang,
          "nama_kasir": kasir,
          "tanggal": tanggal,
          "waktu": waktu,
          "items": items,
        }),
      );
      final data = jsonDecode(response.body);
      return data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }
}
