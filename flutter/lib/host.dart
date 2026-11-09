import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class DesktopHost {
  static const channel = MethodChannel('com.cers.space/desktop');
  static void menuState(Map<String, dynamic> state) {
    if (Platform.isMacOS) {
      channel.invokeMethod('menuState', state).catchError((_) => null);
    }
  }

  static Future<String?> openFile({
    bool multiple = false,
    bool sqliteOnly = false,
  }) async =>
      (await openFiles(multiple: multiple, sqliteOnly: sqliteOnly)).firstOrNull;
  static Future<List<String>> openFiles({
    bool multiple = true,
    bool sqliteOnly = false,
    String? title,
    List<String> extensions = const [],
  }) async => List<String>.from(
    await channel.invokeMethod('openFiles', {
          'multiple': multiple,
          'sqliteOnly': sqliteOnly,
          'title': ?title,
          if (extensions.isNotEmpty) 'extensions': extensions,
        }) ??
        [],
  );
  static Future<String?> saveFile(
    String name, {
    bool sqliteOnly = false,
    String? title,
  }) async => channel.invokeMethod<String>('saveFile', {
    'name': name,
    'sqliteOnly': sqliteOnly,
    'title': ?title,
  });
  static Future<void> reveal(String path) async =>
      channel.invokeMethod('reveal', {'path': path});
  static Future<void> preview(String path) async =>
      channel.invokeMethod('preview', {'path': path});
  static Future<bool> openExternal(Uri uri) async {
    if (!['https', 'mailto'].contains(uri.scheme)) return false;
    return await channel.invokeMethod<bool>('openExternal', {
          'url': uri.toString(),
        }) ??
        false;
  }

  static Future<Map<String, dynamic>> appInfo() async =>
      Map<String, dynamic>.from(await channel.invokeMethod('appInfo') ?? {});

  static Future<bool> systemDark() async {
    try {
      final value = await channel.invokeMethod<bool>('systemAppearance');
      if (value != null) return value;
    } on MissingPluginException {
      // Widget tests use the binding's simulated platform appearance.
    }
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  static Future<void> appearance(bool dark, {bool system = false}) async {
    try {
      await channel.invokeMethod('appearance', {
        'dark': dark,
        'system': system,
      });
    } on MissingPluginException {
      /* Widget tests have no runner. */
    }
  }

  static Future<String?> secret(String id) async =>
      channel.invokeMethod<String>('readSecret', {'id': id});
  static Future<void> saveSecret(String id, String value) async =>
      channel.invokeMethod('writeSecret', {'id': id, 'value': value});
  static Future<Map<String, dynamic>?> decodeRich(String base64) async {
    try {
      return Map<String, dynamic>.from(
        await channel.invokeMethod('decodeRich', {'data': base64}) ?? {},
      );
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> encodeRich(List<Map<String, dynamic>> runs) async =>
      channel.invokeMethod<String>('encodeRich', {'runs': runs});
  static Future<Uint8List?> clipboardImage() async =>
      channel.invokeMethod<Uint8List>('clipboardImage');
  static Future<List<String>> clipboardFiles() async =>
      List<String>.from(await channel.invokeMethod('clipboardFiles') ?? []);
  static String dataDirectory() {
    const override = String.fromEnvironment('SPACE_DATA_DIRECTORY');
    if (override.isNotEmpty) return override;
    final env = Platform.environment;
    if (env['SPACE_FLUTTER_DATA_DIRECTORY']?.isNotEmpty ?? false) {
      return env['SPACE_FLUTTER_DATA_DIRECTORY']!;
    }
    if (Platform.isMacOS) {
      return '${env['HOME']}/Library/Application Support/com.cers.space.flutter';
    }
    if (Platform.isWindows) {
      return '${env['APPDATA'] ?? env['USERPROFILE']}/SpaceFlutter';
    }
    return '${env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share'}/space-flutter';
  }
}
