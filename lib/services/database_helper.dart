import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

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
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // Tabel Produk
    await db.execute('''
    CREATE TABLE produk (
      id TEXT PRIMARY KEY,
      nama TEXT NOT NULL,
      harga INTEGER NOT NULL,
      kategori TEXT NOT NULL
    )
    ''');

    // Tabel Transaksi
    await db.execute('''
    CREATE TABLE transaksi (
      id_transaksi TEXT PRIMARY KEY,
      tanggal TEXT NOT NULL,
      waktu TEXT NOT NULL,
      total INTEGER NOT NULL,
      items_json TEXT NOT NULL,
      status_sync INTEGER NOT NULL
    )
    ''');

    // Masukkan produk dummy awal
    await db.insert('produk', {'id': 'P001', 'nama': 'Kopi Susu', 'harga': 20000, 'kategori': 'Minuman'});
    await db.insert('produk', {'id': 'P002', 'nama': 'Roti Bakar', 'harga': 15000, 'kategori': 'Makanan'});
    await db.insert('produk', {'id': 'P003', 'nama': 'Nasi Goreng', 'harga': 25000, 'kategori': 'Makanan'});
    await db.insert('produk', {'id': 'P004', 'nama': 'Air Mineral', 'harga': 5000, 'kategori': 'Minuman'});
  }

  // --- FUNGSI PRODUK ---
  Future<List<Map<String, dynamic>>> getProduk() async {
    final db = await instance.database;
    return await db.query('produk');
  }

  Future<int> tambahProduk(Map<String, dynamic> produk) async {
    final db = await instance.database;
    return await db.insert('produk', produk);
  }

  Future<int> hapusProduk(String id) async {
    final db = await instance.database;
    return await db.delete('produk', where: 'id = ?', whereArgs: [id]);
  }

  // --- FUNGSI TRANSAKSI ---
  Future<int> simpanTransaksi(Map<String, dynamic> trx) async {
    final db = await instance.database;
    return await db.insert('transaksi', trx);
  }

  Future<List<Map<String, dynamic>>> getTransaksi() async {
    final db = await instance.database;
    return await db.query('transaksi', orderBy: 'tanggal DESC, waktu DESC');
  }

  Future<int> updateStatusSync(String idTransaksi) async {
    final db = await instance.database;
    return await db.update('transaksi', {'status_sync': 1}, where: 'id_transaksi = ?', whereArgs: [idTransaksi]);
  }
}
