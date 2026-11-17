import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'database_helper.dart';

class SyncService with WidgetsBindingObserver {
  SyncService._();
  static final SyncService instance = SyncService._();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _initialized = false;
  bool _syncing = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasNetwork(results)) unawaited(syncPending());
    });
    _retryTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_checkAndSync()));
    await _checkAndSync();
  }

  bool _hasNetwork(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);

  Future<void> _checkAndSync() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (_hasNetwork(results)) await syncPending();
    } catch (_) {
      // A network check failing must not interrupt local checkout or edits.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkAndSync());
  }

  Map<String, dynamic> _payloadForLegacy(Map<String, dynamic> trx, String branch, String cashier) {
    final items = (jsonDecode(trx['items_json']) as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return {
      'action': 'simpanTransaksi',
      'id_transaksi': trx['id_transaksi'].toString(),
      'nama_cabang': branch,
      'nama_kasir': cashier,
      'tanggal': trx['tanggal'].toString(),
      'waktu': trx['waktu'].toString(),
      'metode': trx['metode']?.toString() ?? 'Tunai',
      'items': items,
    };
  }

  Future<Map<String, int>> syncPending({bool force = false}) async {
    if (_syncing) return {'success': 0, 'failed': 0};
    _syncing = true;
    var successCount = 0;
    var failureCount = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('url_appscript') ?? '';
      final branch = prefs.getString('nama_cabang') ?? '';
      final cashier = prefs.getString('nama_kasir') ?? '';
      if (url.isEmpty) return {'success': 0, 'failed': 0};

      // Migrate old pending transactions into the durable outbox.
      final legacy = await DatabaseHelper.instance.getTransaksiBelumSync();
      for (final trx in legacy) {
        try {
          await DatabaseHelper.instance.enqueueSyncOperation(
            id: trx['id_transaksi'].toString(),
            action: 'upsert',
            payload: _payloadForLegacy(trx, branch, cashier),
            replace: false,
          );
        } catch (_) {
          failureCount++;
        }
      }

      if (force) {
        final all = await DatabaseHelper.instance.getTransaksi();
        for (final trx in all) {
          if ((trx['status_sync'] as num).toInt() == 2) continue;
          try {
            await DatabaseHelper.instance.enqueueSyncOperation(
              id: trx['id_transaksi'].toString(),
              action: 'upsert',
              payload: _payloadForLegacy(trx, branch, cashier),
            );
          } catch (_) {
            failureCount++;
          }
        }
      }

      final operations = await DatabaseHelper.instance.getPendingSyncOperations();
      for (final operation in operations) {
        final id = operation['transaction_id'].toString();
        final action = operation['action'].toString();
        try {
          final payload = Map<String, dynamic>.from(jsonDecode(operation['payload_json']) as Map);
          bool ok;
          if (action == 'delete') {
            ok = await ApiService.hapusTransaksi(
              url: url,
              namaCabang: payload['nama_cabang']?.toString() ?? branch,
              idTransaksi: id,
            );
          } else {
            final decodedItems = (payload['items'] as List<dynamic>? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            ok = await ApiService.kirimTransaksi(
              url,
              payload['nama_cabang']?.toString() ?? branch,
              payload['nama_kasir']?.toString() ?? cashier,
              decodedItems,
              payload['metode']?.toString() ?? 'Tunai',
              idTransaksi: id,
              tanggal: payload['tanggal']?.toString(),
              waktu: payload['waktu']?.toString(),
            );
          }
          if (ok) {
            await DatabaseHelper.instance.completeSyncOperation(
              (operation['id'] as num).toInt(), id, action,
            );
            successCount++;
          } else {
            failureCount++;
          }
        } catch (_) {
          failureCount++;
        }
      }
    } finally {
      _syncing = false;
    }
    return {'success': successCount, 'failed': failureCount};
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
