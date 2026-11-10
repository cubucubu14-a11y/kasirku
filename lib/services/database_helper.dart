import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('kasirku_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // Tabel untuk menyimpan transaksi yang belum terkirim (pending)
    await db.execute('''
    CREATE TABLE transaksi_pending (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data_json TEXT NOT NULL
    )
    ''');
  }

  // Simpan transaksi ke antrean lokal
  Future<int> simpanAntrean(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('transaksi_pending', {
      'data_json': jsonEncode(data),
    });
  }

  // Ambil semua transaksi yang tertunda
  Future<List<Map<String, dynamic>>> getAntrean() async {
    final db = await instance.database;
    final result = await db.query('transaksi_pending');
    return result;
  }

  // Hapus transaksi dari antrean setelah berhasil dikirim ke AppScript
  Future<int> hapusAntrean(int id) async {
    final db = await instance.database;
    return await db.delete('transaksi_pending', where: 'id = ?', whereArgs: [id]);
  }
}
