import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Pesan error terakhir (untuk ditampilkan ke pengguna saat debugging)
  static String lastError = '';

  // Helper POST ke Apps Script. Apps Script membalas dengan redirect 302,
  // jadi kita ikuti manual dengan GET ke alamat Location.
  static Future<Map<String, dynamic>?> _post(String url, Map<String, dynamic> body) async {
    lastError = '';
    try {
      var response = await http
          .post(
            Uri.parse(url),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
          response.headers['location'] != null) {
        response = await http
            .get(Uri.parse(response.headers['location']!))
            .timeout(const Duration(seconds: 30));
      }

      if (response.statusCode != 200) {
        lastError = 'HTTP ${response.statusCode}';
        return null;
      }

      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
        lastError = 'Format balasan tidak dikenal';
        return null;
      } catch (_) {
        lastError =
            'Balasan bukan JSON. Cek deploy Apps Script: akses harus "Anyone" dan URL berakhiran /exec';
        return null;
      }
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  static bool _ok(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['status'] == 'success') return true;
    lastError = (data['message'] ?? 'Gagal').toString();
    return false;
  }

  // 1. Daftarkan cabang baru ke Apps Script (buat tab sheet)
  static Future<bool> setupCabang(String url, String namaCabang) async {
    final data = await _post(url, {
      "action": "setupCabang",
      "namaCabang": namaCabang,
    });
    return _ok(data);
  }

  // 2. Kirim transaksi ke Apps Script
  // idTransaksi/tanggal/waktu: isi dengan data transaksi lokal saat sinkron ulang
  static Future<bool> kirimTransaksi(
    String url,
    String namaCabang,
    String kasir,
    List<Map<String, dynamic>> items,
    String? metode, {
    String? idTransaksi,
    String? tanggal,
    String? waktu,
  }) async {
    final now = DateTime.now();
    final tgl = tanggal ??
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final wkt = waktu ??
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    final idTrx = idTransaksi ?? "TRX-${now.millisecondsSinceEpoch}";

    final data = await _post(url, {
      "action": "simpanTransaksi",
      "id_transaksi": idTrx,
      "nama_cabang": namaCabang,
      "nama_kasir": kasir,
      "metode": metode ?? 'Tunai',
      "tanggal": tgl,
      "waktu": wkt,
      "items": items,
    });
    return _ok(data);
  }

  // 3. Void transaksi di Apps Script
  static Future<bool> voidTransaksi(String url, String namaCabang, String idTransaksi) async {
    final data = await _post(url, {
      "action": "voidTransaksi",
      "id_transaksi": idTransaksi,
      "nama_cabang": namaCabang,
    });
    return _ok(data);
  }
}
