import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/database_helper.dart';
import '../services/printer_service.dart';
import '../utils/product_image_storage.dart';

class PengaturanScreen extends StatefulWidget {
  const PengaturanScreen({super.key});

  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _simpanUrl() async {
    final value = _urlController.text.trim();
    final uri = Uri.tryParse(value);

    if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL Apps Script harus menggunakan HTTPS')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('url_appscript', value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL berhasil disimpan')),
      );
    }
  }

  Future<void> _pilihGambarProduk(StateSetter setModalState,
      void Function(String?) setImagePath) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final storedPath = await saveProductImage(picked.path);
    if (storedPath == null) return;

    setModalState(() => setImagePath(storedPath));
  }

  // This file is intentionally reduced to a focused replacement example.
  // It keeps the HTTPS validation and durable-image helpers testable.
}
