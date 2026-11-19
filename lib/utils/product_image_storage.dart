import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveProductImage(String originalPath) async {
  if (originalPath.isEmpty) return null;

  final source = File(originalPath);
  if (!await source.exists()) return null;

  final directory = await getApplicationDocumentsDirectory();
  final productDirectory = Directory(p.join(directory.path, 'product_images'));
  await productDirectory.create(recursive: true);

  final extension = p.extension(originalPath).toLowerCase();
  final safeExtension = ['.jpg', '.jpeg', '.png', '.webp'].contains(extension)
      ? extension
      : '.jpg';
  final destination = File(p.join(
    productDirectory.path,
    'product-${DateTime.now().microsecondsSinceEpoch}$safeExtension',
  ));

  await source.copy(destination.path);
  return destination.path;
}
