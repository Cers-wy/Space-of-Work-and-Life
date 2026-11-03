import 'dart:convert';
import 'dart:io';
import 'package:space_flutter/core/models.dart';
import 'package:space_flutter/core/richtext.dart';

void main() {
  final original = SpaceState.fromJson(
    jsonDecode(File('test/fixtures/05-json-v6.json').readAsStringSync()),
  );
  final runs = FlatRtfd.decode(
    base64Decode(original.tasks.single.richDescription!),
  );
  final directory = Directory('verification/interop')
    ..createSync(recursive: true);
  File(
    '${directory.path}/flutter-roundtrip.rtfd',
  ).writeAsBytesSync(FlatRtfd.encode(runs));
  File(
    '${directory.path}/native-original.rtfd',
  ).writeAsBytesSync(base64Decode(original.tasks.single.richDescription!));
  File(
    '${directory.path}/flutter-portable.json',
  ).writeAsStringSync(swiftJson(original.toJson(portable: true)));
  print('Exported synthetic RTFD and portable bytes');
}
