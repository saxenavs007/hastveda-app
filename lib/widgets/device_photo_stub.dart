import 'package:flutter/material.dart';

/// Web builds have no `dart:io` file images. Couple-reading uses a blob URL.
Widget devicePhoto(String path) {
  return Image.network(
    path,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
  );
}
