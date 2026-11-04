import 'dart:io';
import 'package:flutter/material.dart';
import 'ui/benchmark.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'core/repository.dart';
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
    DesktopHost.channel.setMethodCallHandler((call) async {
      if (call.method == 'accessibilityChanged') {
        await accessibility();
        return;
      }
      if (call.method != 'shortcut') return;
      final c = navigatorKey.currentContext;
      if (c == null || widget.store.modal) return;
      final s = widget.store;
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
          await s.preference('dark', '${!s.dark}');
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
    } else {
      dragActive.value = false;
    }
  }

  @override
  void dispose() {
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
        themeMode: switch (s.appearance) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        },
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
