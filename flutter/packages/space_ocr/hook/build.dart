import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const version = '1.18.1';

void main(List<String> args) async => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  await CBuilder.library(
    name: 'space_ocr_math',
    packageName: input.packageName,
    assetName: 'ocr_math',
    sources: ['src/ocr_math.c'],
  ).run(input: input, output: output);
  final mac = input.config.code.targetOS == OS.macOS;
  final win = input.config.code.targetOS == OS.windows;
  if (!mac && !win) {
    throw UnsupportedError('Space OCR only supports macOS and Windows');
  }
  if (win && input.config.code.targetArchitecture != Architecture.x64) {
    throw UnsupportedError('Space Windows distribution currently targets x64');
  }
  final platform = mac ? 'osx-universal2' : 'win-x64';
  final archiveName = 'onnxruntime-$platform-$version.${mac ? 'tgz' : 'zip'}';
  final libName = mac ? 'libonnxruntime.$version.dylib' : 'onnxruntime.dll';
  final lib = File.fromUri(
    input.outputDirectoryShared.resolve(
      '$version/$platform/${input.config.code.targetArchitecture}/$libName',
    ),
  );
  if (!await lib.exists()) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final archive = File.fromUri(
        input.outputDirectoryShared.resolve(archiveName),
      );
      await archive.parent.create(recursive: true);
      final localArchive = Platform.environment['SPACE_ORT_ARCHIVE'];
      if (localArchive != null) {
        await File(localArchive).copy(archive.path);
      } else if (!await archive.exists()) {
        final proxy =
            Platform.environment['HTTPS_PROXY'] ??
            Platform.environment['https_proxy'];
        if (proxy != null) {
          final parsed = Uri.parse(proxy);
          client.findProxy = (_) => 'PROXY ${parsed.host}:${parsed.port}';
        }
        final uri = Uri.parse(
          'https://github.com/microsoft/onnxruntime/releases/download/v$version/$archiveName',
        );
        final response = await (await client.getUrl(uri))
            .close()
            .timeout(const Duration(seconds: 45));
        if (response.statusCode != 200) {
          throw StateError(
            'ONNX runtime download failed: ${response.statusCode}',
          );
        }
        final sink = archive.openWrite();
        try {
          await sink.addStream(response.timeout(const Duration(seconds: 45)));
        } finally {
          await sink.close();
        }
      }
      final bytes = await archive.readAsBytes();
      final expected = mac
          ? '014f6332da3fa51926c57ca973c2d03ceebae069a537f55765848260ab4bf8f7'
          : windowsArchiveHash;
      if (sha256.convert(bytes).toString() != expected) {
        throw StateError('ONNX runtime SHA256 mismatch');
      }
      final decoded = mac
          ? TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes))
          : ZipDecoder().decodeBytes(bytes);
      final entry = decoded.findFile(
        'onnxruntime-$platform-$version/lib/$libName',
      );
      if (entry == null) {
        throw StateError('ONNX runtime archive is missing $libName');
      }
      await lib.parent.create(recursive: true);
      await lib.writeAsBytes(entry.content as List<int>, flush: true);
      if (mac) {
        final architecture =
            input.config.code.targetArchitecture == Architecture.arm64
            ? 'arm64'
            : 'x86_64';
        final thin = '${lib.path}.thin';
        final result = await Process.run('lipo', [
          lib.path,
          '-thin',
          architecture,
          '-output',
          thin,
        ]);
        if (result.exitCode != 0)
          throw StateError(
            'Unable to select ONNX architecture: ${result.stderr}',
          );
        await File(thin).rename(lib.path);
      }
    } finally {
      client.close(force: true);
    }
  }
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'onnxruntime',
      linkMode: DynamicLoadingBundled(),
      file: lib.uri,
    ),
  );
});

// Filled from the official archive by the integration script, not from a mirror.
const windowsArchiveHash =
    '53fb7226fe3cf16001afd1eae79e35f891a20e80bd686185d62ea878e6f9b1a6';
