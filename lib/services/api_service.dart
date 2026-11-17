import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ApiService {
  static String lastError = '';

  static Future<Map<String, dynamic>?> _post(
    String url,
    Map<String, dynamic> body,
  ) async {
    lastError = '';
    try {
      var response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
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
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        lastError = 'Format balasan server tidak dikenal';
        return null;
      } catch (_) {
        lastError =
            'Balasan bukan JSON. Periksa deployment Apps Script (/exec, akses Anyone).';
        return null;
      }
    } catch (error) {
      lastError = error.toString();
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
    final data = await _post(url, {
      'action': 'setupCabang',
      'namaCabang': namaCabang,
    });
    return _ok(data);
  }

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
        DateFormat('yyyy-MM-dd').format(now);
    final wkt = waktu ?? DateFormat('HH:mm:ss').format(now);
    final data = await _post(url, {
      'action': 'simpanTransaksi',
      'id_transaksi': idTransaksi ?? 'TRX-${now.millisecondsSinceEpoch}',
      'nama_cabang': namaCabang,
      'nama_kasir': kasir,
      'metode': metode ?? 'Tunai',
      'tanggal': tgl,
      'waktu': wkt,
      'items': items,
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
  }) async {
    final data = await _post(url, {
      'action': 'editTransaksi',
      'nama_cabang': namaCabang,
      'id_transaksi': idTransaksi,
      'tanggal': tanggal,
      'waktu': waktu,
      'total': total,
      'metode': metode,
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

  static Future<bool> voidTransaksi(
    String url,
    String namaCabang,
    String idTransaksi,
  ) async {
    final data = await _post(url, {
      'action': 'voidTransaksi',
      'id_transaksi': idTransaksi,
      'nama_cabang': namaCabang,
    });
    return _ok(data);
  }
}
