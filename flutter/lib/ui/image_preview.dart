import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Keeps encoded bytes stable across editor selection/formatting rebuilds.
/// Only the preview is downsampled; the document retains its original bytes.
class RichImagePreview extends StatefulWidget {
  final String source;
  const RichImagePreview({super.key, required this.source});

  @override
  State<RichImagePreview> createState() => _RichImagePreviewState();
}

class _RichImagePreviewState extends State<RichImagePreview> {
  Uint8List? bytes;
  ImageProvider? provider;
  int width = 0, height = 0;

  @override
  void initState() {
    super.initState();
    decode();
  }

  void decode() {
    try {
      bytes = base64Decode(widget.source);
    } on FormatException {
      bytes = null;
    }
  }

  void release() {
    // Evict only this preview. Do not flush unrelated application images.
    provider?.evict();
    provider = null;
  }

  @override
  void didUpdateWidget(RichImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      release();
      decode();
    }
  }

  @override
  void dispose() {
    release();
    bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (bytes == null) return const Text('图片无法预览，原字节已保留');
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final logicalWidth = constraints.maxWidth.clamp(1.0, 480.0);
      final targetWidth = (logicalWidth * ratio).ceil();
      final targetHeight = (240 * ratio).ceil();
      if (provider == null || width != targetWidth || height != targetHeight) {
        release();
        width = targetWidth;
        height = targetHeight;
        provider = ResizeImage(
          MemoryImage(bytes!),
          width: width,
          height: height,
          policy: ResizeImagePolicy.fit,
        );
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 240),
        child: Image(
          image: provider!,
          fit: BoxFit.scaleDown,
          errorBuilder: (c, e, s) => const Text('图片无法预览，原字节已保留'),
        ),
      );
    },
  );
}
