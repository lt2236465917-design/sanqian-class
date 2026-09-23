import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:scoped_model/scoped_model.dart';

import 'generated/l10n.dart';
import 'Models/PersonalSchedule.dart';
import 'Pages/Personal/PersonalHomeView.dart';
import 'Resources/Constant.dart';
import 'Resources/PersonalTheme.dart';
import 'Utils/States/MainState.dart';
import 'Utils/InitUtil.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  final themeConf = await InitUtil.initialize();
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
    MyApp(themeConf[0], Constant.themeModeList[themeConf[1]], themeConf[2]),
  );
}

class MyApp extends StatefulWidget {
  final int themeIndex;
  final ThemeMode themeMode;
  final String themeCustom;
  final Future<PersonalSchedule> Function()? scheduleLoader;
  final DateTime Function()? clock;

  const MyApp(
    this.themeIndex,
    this.themeMode,
    this.themeCustom, {
    super.key,
    this.scheduleLoader,
    this.clock,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final MainStateModel _model;
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _widgetChannel = MethodChannel('sanqian/widget');

  @override
  void initState() {
    super.initState();
    _model = MainStateModel()..initThemeState();
    if (Platform.isAndroid) {
      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'openSchedule') {
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
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
        home: PersonalHomeView(
          loader: widget.scheduleLoader,
          clock: widget.clock,
        ),
      ),
    ),
  );
}
