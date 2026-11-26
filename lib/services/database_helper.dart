import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kasirku_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    return openDatabase(join(dbPath, filePath), version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''CREATE TABLE produk (id TEXT PRIMARY KEY, nama TEXT NOT NULL, harga INTEGER NOT NULL, kategori TEXT NOT NULL, gambar TEXT DEFAULT '')''');
    await db.execute('''CREATE TABLE transaksi (id_transaksi TEXT PRIMARY KEY, tanggal TEXT NOT NULL, waktu TEXT NOT NULL, total INTEGER NOT NULL, items_json TEXT NOT NULL, status_sync INTEGER NOT NULL, metode TEXT DEFAULT 'Tunai')''');
    await _createSyncQueue(db);
    await _seedProducts(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute("ALTER TABLE transaksi ADD COLUMN metode TEXT DEFAULT 'Tunai'"); } catch (_) {}
      try { await db.execute("ALTER TABLE produk ADD COLUMN gambar TEXT DEFAULT ''"); } catch (_) {}
    }
    if (oldVersion < 3) await _createSyncQueue(db);
  }

  Future<void> _createSyncQueue(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, transaction_id TEXT NOT NULL UNIQUE, action TEXT NOT NULL, payload_json TEXT NOT NULL, created_at TEXT NOT NULL)''');
  }

  Future<void> _seedProducts(DatabaseExecutor db) async {
    await db.insert('produk', {'id': 'P001', 'nama': 'Kopi Susu', 'harga': 20000, 'kategori': 'Minuman'});
    await db.insert('produk', {'id': 'P002', 'nama': 'Roti Bakar', 'harga': 15000, 'kategori': 'Makanan'});
    await db.insert('produk', {'id': 'P003', 'nama': 'Nasi Goreng', 'harga': 25000, 'kategori': 'Makanan'});
    await db.insert('produk', {'id': 'P004', 'nama': 'Air Mineral', 'harga': 5000, 'kategori': 'Minuman'});
  }

  // --- FUNGSI PRODUK ---
  Future<List<Map<String, dynamic>>> getProduk() async => (await database).query('produk');
  Future<int> tambahProduk(Map<String, dynamic> data) async => (await database).insert('produk', data);
  Future<int> editProduk(Map<String, dynamic> data) async => (await database).update('produk', data, where: 'id = ?', whereArgs: [data['id']]);
  Future<int> hapusProduk(String id) async => (await database).delete('produk', where: 'id = ?', whereArgs: [id]);

  // --- FUNGSI TRANSAKSI ---
  Future<int> simpanTransaksi(Map<String, dynamic> trx) async => (await database).insert('transaksi', trx);

  Future<void> simpanTransaksiOffline(Map<String, dynamic> trx, Map<String, dynamic> payload) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('transaksi', trx);
      await _queue(txn, trx['id_transaksi'].toString(), 'upsert', payload);
    });
  }

  Future<int> editTransaksi(Map<String, dynamic> trx) async => (await database).update('transaksi', trx, where: 'id_transaksi = ?', whereArgs: [trx['id_transaksi']]);

  Future<void> editTransaksiOffline(Map<String, dynamic> trx, Map<String, dynamic> payload) async {
    final db = await database;
    await db.transaction((txn) async {
      final local = Map<String, dynamic>.from(trx)..['status_sync'] = 0;
      await txn.update('transaksi', local, where: 'id_transaksi = ?', whereArgs: [trx['id_transaksi']]);
      await _queue(txn, trx['id_transaksi'].toString(), 'upsert', payload);
    });
  }

  Future<void> hapusTransaksiOffline(String id, Map<String, dynamic> payload) async {
    final db = await database;
    await db.transaction((txn) async {
      await _queue(txn, id, 'delete', payload);
      await txn.delete('transaksi', where: 'id_transaksi = ?', whereArgs: [id]);
    });
  }

  Future<void> _queue(DatabaseExecutor db, String id, String action, Map<String, dynamic> payload) async {
    await db.insert('sync_queue', {'transaction_id': id, 'action': action, 'payload_json': jsonEncode(payload), 'created_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> enqueueSyncOperation({required String id, required String action, required Map<String, dynamic> payload, bool replace = true}) async {
    final db = await database;
    await db.insert('sync_queue', {'transaction_id': id, 'action': action, 'payload_json': jsonEncode(payload), 'created_at': DateTime.now().toIso8601String()}, conflictAlgorithm: replace ? ConflictAlgorithm.replace : ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getPendingSyncOperations() async => (await database).query('sync_queue', orderBy: 'created_at ASC');

  Future<void> completeSyncOperation(int queueId, String transactionId, String action) async {
    final db = await database;
    await db.transaction((txn) async {
      final removed = await txn.delete('sync_queue', where: 'id = ?', whereArgs: [queueId]);
      if (removed > 0 && action == 'upsert') await txn.update('transaksi', {'status_sync': 1}, where: 'id_transaksi = ?', whereArgs: [transactionId]);
    });
  }

  // --- FUNGSI GET TRANSAKSI (DIPERBARUI) ---
  Future<List<Map<String, dynamic>>> getTransaksi({String? filterTanggal}) async {
    final db = await database;
    if (filterTanggal != null && filterTanggal.isNotEmpty) {
      if (filterTanggal.length == 7) {
        // Filter Bulan (format YYYY-MM)
        return db.query('transaksi', where: 'tanggal LIKE ?', whereArgs: ['$filterTanggal%'], orderBy: 'tanggal DESC, waktu DESC');
      } else {
        // Filter Tanggal Spesifik (format YYYY-MM-DD)
        return db.query('transaksi', where: 'tanggal = ?', whereArgs: [filterTanggal], orderBy: 'tanggal DESC, waktu DESC');
      }
    }
    return db.query('transaksi', orderBy: 'tanggal DESC, waktu DESC');
  }

  // FUNGSI BARU: Filter Rentang Tanggal (Mulai - Selesai)
  Future<List<Map<String, dynamic>>> getTransaksiRange({String? startDate, String? endDate}) async {
    final db = await database;
    if (startDate != null && endDate != null) {
      return db.query(
        'transaksi',
        where: 'tanggal >= ? AND tanggal <= ?',
        whereArgs: [startDate, endDate],
        orderBy: 'tanggal DESC, waktu DESC',
      );
    }
    return db.query('transaksi', orderBy: 'tanggal DESC, waktu DESC');
  }

  Future<List<Map<String, dynamic>>> getTransaksiBelumSync() async => (await database).query('transaksi', where: 'status_sync = ?', whereArgs: [0], orderBy: 'tanggal ASC, waktu ASC');
  Future<int> updateStatusSync(String id) async => (await database).update('transaksi', {'status_sync': 1}, where: 'id_transaksi = ?', whereArgs: [id]);
  Future<int> updateStatusSyncPending(String id) async => (await database).update('transaksi', {'status_sync': 0}, where: 'id_transaksi = ?', whereArgs: [id]);
  
  // FUNGSI HAPUS TRANSAKSI + ANTREAN
  Future<int> hapusTransaksi(String id) async {
    final db = await database;
    return await db.transaction((txn) async {
      final res = await txn.delete('transaksi', where: 'id_transaksi = ?', whereArgs: [id]);
      await txn.delete('sync_queue', where: 'transaction_id = ?', whereArgs: [id]);
      return res;
    });
  }

  Future<int> voidTransaksiLokal(String id) async => (await database).update('transaksi', {'status_sync': 2}, where: 'id_transaksi = ?', whereArgs: [id]);
}
