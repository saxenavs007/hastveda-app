import 'dart:io';

import 'package:flutter/widgets.dart';

Widget buildLocalFileImage({
  required String path,
  double? height,
  double? width,
  BoxFit? fit,
  Color? color,
  String? semanticLabel,
  required Widget fallback,
}) {
  return Image.file(
    File(path),
    height: height,
    width: width,
    fit: fit ?? BoxFit.cover,
    color: color,
    semanticLabel: semanticLabel,
    errorBuilder: (_, __, ___) => fallback,
  );
}
