import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ApiService {
  static String lastError = '';

  static Future<Map<String, dynamic>?> _post(String url, Map<String, dynamic> body) async {
    lastError = '';

    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
      lastError = 'URL harus menggunakan HTTPS';
      return null;
    }

    try {
      var response = await http.post(uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      if ([301, 302, 303, 307, 308].contains(response.statusCode) &&
          response.headers['location'] != null) {
        final location = Uri.tryParse(response.headers['location']!);
        if (location == null || location.scheme != 'https') {
          lastError = 'Redirect server tidak aman';
          return null;
        }
        response = await http.get(location).timeout(const Duration(seconds: 30));
      }

      if (response.statusCode != 200) {
        lastError = 'HTTP ${response.statusCode}';
        return null;
      }

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        lastError = 'Format balasan server tidak dikenal';
        return null;
      } catch (_) {
        lastError = 'Balasan bukan JSON.';
        return null;
      }
    } catch (_) {
      lastError = 'Gagal terhubung ke server atau respons terlambat';
      return null;
    }
  }

  static bool _ok(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['status'] == 'success') return true;
    lastError = (data['message'] ?? 'Permintaan gagal').toString();
    return false;
  }

  static Future<bool> setupCabang(String url, String namaCabang) async {
    final data = await _post(url, {'action': 'setupCabang', 'namaCabang': namaCabang});
    return _ok(data);
  }

  // --- PERBAIKAN: Fungsi kirim transaksi yang lebih aman ---
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
    final tgl = tanggal ?? DateFormat('yyyy-MM-dd').format(now);
    final wkt = waktu ?? DateFormat('HH:mm:ss').format(now);
    
    // Pastikan item di-encode dengan aman dan bersih
    final safeItems = items.map((e) => {
      'nama': e['nama'].toString(),
      'qty': (e['qty'] as num).toInt(),
      'harga': (e['harga'] as num).toInt(),
    }).toList();

    final data = await _post(url, {
      'action': 'simpanTransaksi',
      'id_transaksi': idTransaksi ?? 'TRX-${now.millisecondsSinceEpoch}',
      'nama_cabang': namaCabang,
      'nama_kasir': kasir,
      'metode': metode ?? 'Tunai',
      'tanggal': tgl,
      'waktu': wkt,
      'items': safeItems,
    });
    return _ok(data);
  }

  static Future<bool> editTransaksi({
    required String url,
    required String namaCabang,
    required String idTransaksi,
    required String tanggal,
    required String waktu,
    required int total,
    required String metode,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = await _post(url, {
      'action': 'editTransaksi',
      'nama_cabang': namaCabang,
      'id_transaksi': idTransaksi,
      'tanggal': tanggal,
      'waktu': waktu,
      'total': total,
      'metode': metode,
      'items': items,
    });
    return _ok(data);
  }

  static Future<bool> hapusTransaksi({
    required String url,
    required String namaCabang,
    required String idTransaksi,
  }) async {
    final data = await _post(url, {
      'action': 'hapusTransaksi',
      'nama_cabang': namaCabang,
      'id_transaksi': idTransaksi,
    });
    return _ok(data);
  }

  static Future<bool> voidTransaksi(String url, String namaCabang, String idTransaksi) async {
    final data = await _post(url, {
      'action': 'voidTransaksi',
      'id_transaksi': idTransaksi,
      'nama_cabang': namaCabang,
    });
    return _ok(data);
  }

  // --- FUNGSI BARU UNTUK CEK PIN OWNER ---
  static Future<bool> cekPinOwner(String url, String namaCabang, String pin) async {
    final data = await _post(url, {
      'action': 'cekPinOwner',
      'nama_cabang': namaCabang,
      'pin': pin,
    });
    return _ok(data);
  }
  // ----------------------------------------

  static Future<List<String>?> getDataIdsForDate(String url, String namaCabang, String tanggal) async {
    final data = await _post(url, {
      'action': 'get-data-kasir',
      'nama_cabang': namaCabang,
      'tanggal': tanggal,
    });
    if (data == null || data['status'] != 'success') return null;
    if (data['data'] is List) {
      return (data['data'] as List).map((e) => e.toString()).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>?> tarikTransaksi(String url, String namaCabang, String idTransaksi) async {
    final data = await _post(url, {
      'action': 'tarikTransaksi',
      'nama_cabang': namaCabang,
      'id_transaksi': idTransaksi,
    });
    if (data == null || data['status'] != 'success') return null;
    return data['data'] as Map<String, dynamic>?;
  }

  static Future<List<Map<String, dynamic>>?> tarikSemuaData(String url, String namaCabang) async {
    final data = await _post(url, {
      'action': 'tarikSemuaData',
      'nama_cabang': namaCabang,
    });
    if (data == null || data['status'] != 'success') return null;
    if (data['data'] is List) {
      return (data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}
