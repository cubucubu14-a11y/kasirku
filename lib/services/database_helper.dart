import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
    return openDatabase(
      join(dbPath, filePath),
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE produk (
        id TEXT PRIMARY KEY,
        nama TEXT NOT NULL,
        harga INTEGER NOT NULL,
        kategori TEXT NOT NULL,
        gambar TEXT DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE transaksi (
        id_transaksi TEXT PRIMARY KEY,
        tanggal TEXT NOT NULL,
        waktu TEXT NOT NULL,
        total INTEGER NOT NULL,
        items_json TEXT NOT NULL,
        status_sync INTEGER NOT NULL,
        metode TEXT DEFAULT 'Tunai'
      )
    ''');
    await db.insert('produk', {'id': 'P001', 'nama': 'Kopi Susu', 'harga': 20000, 'kategori': 'Minuman'});
    await db.insert('produk', {'id': 'P002', 'nama': 'Roti Bakar', 'harga': 15000, 'kategori': 'Makanan'});
    await db.insert('produk', {'id': 'P003', 'nama': 'Nasi Goreng', 'harga': 25000, 'kategori': 'Makanan'});
    await db.insert('produk', {'id': 'P004', 'nama': 'Air Mineral', 'harga': 5000, 'kategori': 'Minuman'});
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute("ALTER TABLE transaksi ADD COLUMN metode TEXT DEFAULT 'Tunai'"); } catch (_) {}
      try { await db.execute("ALTER TABLE produk ADD COLUMN gambar TEXT DEFAULT ''"); } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> getProduk() async =>
      (await instance.database).query('produk');

  Future<int> tambahProduk(Map<String, dynamic> produk) async =>
      (await instance.database).insert('produk', produk);

  Future<int> editProduk(Map<String, dynamic> produk) async =>
      (await instance.database).update('produk', produk, where: 'id = ?', whereArgs: [produk['id']]);

  Future<int> hapusProduk(String id) async =>
      (await instance.database).delete('produk', where: 'id = ?', whereArgs: [id]);

  Future<int> simpanTransaksi(Map<String, dynamic> trx) async =>
      (await instance.database).insert('transaksi', trx);

  Future<int> editTransaksi(Map<String, dynamic> trx) async =>
      (await instance.database).update(
        'transaksi',
        trx,
        where: 'id_transaksi = ?',
        whereArgs: [trx['id_transaksi']],
      );

  Future<int> hapusTransaksi(String idTransaksi) async =>
      (await instance.database).delete(
        'transaksi',
        where: 'id_transaksi = ?',
        whereArgs: [idTransaksi],
      );

  Future<List<Map<String, dynamic>>> getTransaksi({String? filterTanggal}) async {
    final db = await instance.database;
    if (filterTanggal != null && filterTanggal.isNotEmpty) {
      return db.query(
        'transaksi',
        where: 'tanggal LIKE ?',
        whereArgs: ['$filterTanggal%'],
        orderBy: 'tanggal DESC, waktu DESC',
      );
    }
    return db.query('transaksi', orderBy: 'tanggal DESC, waktu DESC');
  }

  Future<List<Map<String, dynamic>>> getTransaksiBelumSync() async =>
      (await instance.database).query(
        'transaksi',
        where: 'status_sync = ?',
        whereArgs: [0],
        orderBy: 'tanggal ASC, waktu ASC',
      );

  Future<int> updateStatusSync(String idTransaksi) async =>
      (await instance.database).update(
        'transaksi',
        {'status_sync': 1},
        where: 'id_transaksi = ?',
        whereArgs: [idTransaksi],
      );

  Future<int> voidTransaksiLokal(String idTransaksi) async =>
      (await instance.database).update(
        'transaksi',
        {'status_sync': 2},
        where: 'id_transaksi = ?',
        whereArgs: [idTransaksi],
      );
}
