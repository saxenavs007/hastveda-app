import 'dart:io';

import 'package:flutter/widgets.dart';

Widget devicePhoto(String path) {
  return Image.file(File(path), fit: BoxFit.cover);
}
