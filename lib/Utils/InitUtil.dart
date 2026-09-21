import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../Models/CourseTableModel.dart';
import '../Resources/Config.dart';
import '../Utils/ColorUtil.dart';
import '../Utils/WeekUtil.dart';
import '../core/widget_data/services/unified_data_service.dart';
import '../core/widget_data/communication/native_data_bridge.dart';

class InitUtil {
  static Future<List> initialize() async {
    int themeIndex = await getTheme();
    int themeModeIndex = await getThemeMode();
    String themeCustom = await getThemeCustom();
    await checkDataBase();
    await WeekUtil.checkWeek();
    await ColorPool.checkColorPool();

    // 初始化 Widget 数据
    await initializeWidgetData();

    return [themeIndex, themeModeIndex, themeCustom];
  }

  /// 初始化 Widget 数据
  static Future<void> initializeWidgetData() async {
    try {
      // 仅在 iOS 平台执行
      if (!Platform.isIOS) return;

      final platformInfo = await NativeDataBridge().getPlatformInfo();
      if (platformInfo?['supportsWidgets'] != true) return;

      final preferences = await SharedPreferences.getInstance();
      final widgetService = UnifiedDataService(preferences: preferences);

      // 更新 Widget 数据
      final success = await widgetService.updateWidgetData();
      if (success) {
        print('Widget data initialized successfully');
      } else {
        print('Failed to initialize widget data');
      }
    } catch (e) {
      print('Error initializing widget data: $e');
    }
  }

  static Future<int> getTheme() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    int? themeIndex = sp.getInt("themeIndex");
    if (themeIndex != null) {
      return themeIndex;
    }
    return 0;
  }

  static Future<int> getThemeMode() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    int? themeModeIndex = sp.getInt("themeModeIndex");
    if (themeModeIndex != null) {
      return themeModeIndex;
    }
    return 0;
  }

  static Future<String> getThemeCustom() async {
    SharedPreferences sp = await SharedPreferences.getInstance();
    String? themeCustom = sp.getString("themeCustomColor");
    if (themeCustom != null) {
      return themeCustom;
    }
    return '';
  }

  static checkDataBase() async {
    CourseTableProvider courseTableProvider = CourseTableProvider();
    List c = await courseTableProvider.getAllCourseTable();
    if (c.isEmpty) {
      await courseTableProvider.insert(CourseTable(Config.default_class_table));
    }
  }
}
