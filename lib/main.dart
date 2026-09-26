import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:scoped_model/scoped_model.dart';

import 'generated/l10n.dart';
import 'Models/PersonalSchedule.dart';
import 'Pages/Personal/PersonalHomeView.dart';
import 'Pages/Personal/Widgets/ColdStartMascotSplash.dart';
import 'Resources/Constant.dart';
import 'Resources/PersonalTheme.dart';
import 'Utils/States/MainState.dart';
import 'Utils/InitUtil.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Android keeps the launch screen until the first frame is allowed.
  // iOS must draw immediately: deferring the frame holds the white system card.
  if (Platform.isAndroid) {
    FlutterNativeSplash.preserve(widgetsBinding: binding);
  }
  final startupInitialization = InitUtil.initialize();
  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(
    MyApp(
      0,
      Constant.themeModeList[0],
      '',
      startupInitialization: startupInitialization,
    ),
  );
}

class MyApp extends StatefulWidget {
  final int themeIndex;
  final ThemeMode themeMode;
  final String themeCustom;
  final Future<PersonalSchedule> Function()? scheduleLoader;
  final DateTime Function()? clock;
  final Future<List>? startupInitialization;

  const MyApp(
    this.themeIndex,
    this.themeMode,
    this.themeCustom, {
    super.key,
    this.scheduleLoader,
    this.clock,
    this.startupInitialization,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final MainStateModel _model;
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _widgetChannel = MethodChannel('sanqian/widget');
  static const _mascotSplashChannel = MethodChannel('sanqian/mascot_splash');
  bool _startupReady = false;

  @override
  void initState() {
    super.initState();
    _model = MainStateModel()..initThemeState();
    final initialization = widget.startupInitialization;
    if (initialization == null) {
      _startupReady = true;
    } else {
      initialization.then<void>(
        (_) {
          if (mounted) setState(() => _startupReady = true);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('App startup initialization failed: $error');
          if (mounted) setState(() => _startupReady = true);
        },
      );
    }
    if (Platform.isIOS) {
      _mascotSplashChannel.setMethodCallHandler((call) async {
        if (call.method == 'releaseFirstFrame') {
          FlutterNativeSplash.remove();
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startNativeMascotPlayback());
      });
      // Native dismiss also releases the frame. This only covers a missed call.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 12), FlutterNativeSplash.remove),
      );
    }
    if (Platform.isAndroid) {
      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'openSchedule') {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  Future<void> _startNativeMascotPlayback() async {
    try {
      await _mascotSplashChannel.invokeMethod<void>('startPlayback');
    } catch (error) {
      debugPrint('Unable to start native mascot splash: $error');
      FlutterNativeSplash.remove();
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      _widgetChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScopedModel<MainStateModel>(
    model: _model,
    child: ScopedModelDescendant<MainStateModel>(
      builder: (context, child, model) => MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: personalAppName,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        theme: personalTheme(Brightness.light),
        darkTheme: personalTheme(Brightness.dark),
        themeMode: model.themeMode ?? widget.themeMode,
        home: widget.startupInitialization == null
            ? PersonalHomeView(
                loader: widget.scheduleLoader,
                clock: widget.clock,
              )
            : Platform.isIOS
            ? _startupReady
                  ? PersonalHomeView(
                      loader: widget.scheduleLoader,
                      clock: widget.clock,
                    )
                  : const Center(child: CircularProgressIndicator.adaptive())
            : ColdStartMascotSplash(
                onNativeSplashReady: FlutterNativeSplash.remove,
                child: _startupReady
                    ? PersonalHomeView(
                        loader: widget.scheduleLoader,
                        clock: widget.clock,
                      )
                    : const Center(child: CircularProgressIndicator.adaptive()),
              ),
      ),
    ),
  );
}
