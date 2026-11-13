import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'ui/benchmark.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'core/repository.dart';
import 'core/drive.dart';
import 'ui/file_drive.dart';
import 'core/sync_service.dart';
import 'host.dart';
import 'store.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';
import 'ui/dialogs.dart';
import 'core/models.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SpaceStore(
    SpaceRepository(Directory(DesktopHost.dataDirectory())),
  );
  await store.initialize();
  const demo = bool.fromEnvironment('SPACE_DEMO');
  const count = int.fromEnvironment('SPACE_DEMO_COUNT', defaultValue: 9);
  if (demo) {
    const isolated = String.fromEnvironment('SPACE_DATA_DIRECTORY');
    if (isolated.isEmpty) throw StateError('SPACE_DEMO需要显式隔离数据目录');
    if (store.state.tasks.isEmpty) {
      await store.commit(demoState(count: count), '验收演示数据已载入');
      await store.reload();
    }
  }
  runApp(SpaceApp(store: store));
  unawaited(
    driveFor(store).initialize().catchError((Object error) {
      driveFor(store).message = driveError(error);
      driveFor(store).changed();
    }),
  );
  if (const bool.fromEnvironment("SPACE_BENCHMARK")) {
    WidgetsBinding.instance.addPostFrameCallback((_) => runUiBenchmark(store));
  }
  await syncFor(store).initialize();
}

class SpaceApp extends StatefulWidget {
  final SpaceStore store;
  const SpaceApp({super.key, required this.store});
  @override
  State<SpaceApp> createState() => _SpaceAppState();
}

class _SpaceAppState extends State<SpaceApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  bool reducedTransparency = false, reducedMotion = false;
  bool _askingExit = false, _exitWhenDone = false;
  final _exitTasks = <String>{};
  DriveService get drive => driveFor(widget.store);
  void _driveChanged() {
    DesktopHost.channel
        .invokeMethod('driveState', {'active': drive.active})
        .catchError((_) => null);
    if (_exitWhenDone && !drive.active) {
      _exitWhenDone = false;
      if (drive.tasks
          .where((t) => _exitTasks.contains(t.id))
          .every((t) => t.status == UploadStatus.complete)) {
        DesktopHost.channel.invokeMethod('finishClose').catchError((_) => null);
      } else {
        drive.message = '部分上传未完成，已取消自动退出。';
        drive.changed();
      }
    }
  }

  Future<void> _requestExit() async {
    if (_askingExit) return;
    _askingExit = true;
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final answer = await showUploadExit(
        context,
        drive.tasks.where((t) => t.status.active).length,
      );
      if (answer == 'wait') {
        _exitTasks
          ..clear()
          ..addAll(drive.tasks.where((t) => t.status.active).map((t) => t.id));
        _exitWhenDone = true;
        _driveChanged();
      } else if (answer == 'stop') {
        await drive.stop();
        await DesktopHost.channel.invokeMethod('finishClose');
      }
    } finally {
      _askingExit = false;
    }
  }

  Future<void> accessibility() async {
    try {
      final values = Map<String, dynamic>.from(
        await DesktopHost.channel.invokeMethod('accessibility') ?? {},
      );
      if (mounted) {
        setState(() {
          reducedTransparency = values['reduceTransparency'] == true;
          reducedMotion = values['reduceMotion'] == true;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    accessibility();
    drive.addListener(_driveChanged);
    _driveChanged();
    DesktopHost.channel.setMethodCallHandler((call) async {
      if (call.method == 'requestClose') {
        await _requestExit();
        return;
      }
      if (call.method == 'systemAppearanceChanged') {
        await widget.store.updateSystemAppearance();
        return;
      }
      if (call.method == 'accessibilityChanged') {
        await accessibility();
        return;
      }
      if (call.method != 'shortcut') return;
      final c = navigatorKey.currentContext;
      if (c == null || widget.store.modal) return;
      final s = widget.store;
      if (s.area != SpaceArea.tasks &&
          const {
            'new',
            'reload',
            'statuses',
            'undo',
            'overview',
            'board',
            'list',
            'gantt',
            'calendar',
          }.contains(call.arguments)) {
        return;
      }
      switch (call.arguments) {
        case 'search':
          s.searchRequested.value++;
        case 'reload':
          await s.reload();
        case 'new':
          await editTask(c, s, SpaceTask.create(projectID: s.query.projectID));
        case 'settings':
          await showSettings(c, s);
        case 'help':
          await showHelp(c, s);
        case 'statuses':
          await showStatuses(c, s);
        case 'undo':
          await s.undo();
        case 'nav':
          await s.preference('navCollapsed', '${!s.navCollapsed}');
        case 'overview':
          await s.preference('overviewCollapsed', '${!s.overviewCollapsed}');
        case 'theme':
          await s.toggleTheme();
        case 'board':
        case 'list':
        case 'gantt':
        case 'calendar':
          await s.preference('viewMode', call.arguments as String);
      }
    });
  }

  @override
  void didChangePlatformBrightness() {
    widget.store.updateSystemAppearance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.refreshDay();
      widget.store.updateSystemAppearance();
    } else {
      dragActive.value = false;
    }
  }

  @override
  void dispose() {
    drive.removeListener(_driveChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: widget.store,
    builder: (c, child) {
      final s = widget.store;
      DesktopHost.menuState({
        'modal': s.modal,
        'area': s.area.name,
        'loaded': s.loaded,
        'canUndo': s.canUndo,
        'navCollapsed': s.navCollapsed,
        'overviewCollapsed': s.overviewCollapsed,
        'dark': s.dark,
      });
      return MaterialApp(
        title: 'Space',
        scrollBehavior: SpaceScrollBehavior(hidden: s.hideScrollbars),
        navigatorKey: navigatorKey,
        builder: (c, child) => SpaceAccessibility(
          reduceTransparency: reducedTransparency,
          child: MediaQuery(
            data: MediaQuery.of(c).copyWith(
              disableAnimations:
                  reducedMotion || MediaQuery.of(c).disableAnimations,
            ),
            child: child!,
          ),
        ),
        debugShowCheckedModeBanner: false,
        theme: spaceTheme(false),
        darkTheme: spaceTheme(true),
        themeMode: s.dark ? ThemeMode.dark : ThemeMode.light,
        themeAnimationDuration:
            reducedMotion ||
                WidgetsBinding
                    .instance
                    .platformDispatcher
                    .accessibilityFeatures
                    .disableAnimations
            ? Duration.zero
            : spaceDuration,
        themeAnimationCurve: spaceCurve,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(body: Workspace(store: widget.store)),
      );
    },
  );
}
