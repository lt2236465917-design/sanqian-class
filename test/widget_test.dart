import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wheretosleepinnju/Pages/Personal/PersonalHomeView.dart';
import 'package:wheretosleepinnju/Pages/Personal/Widgets/FloatingScheduleNavigation.dart';
import 'package:wheretosleepinnju/main.dart';

import 'Models/personal_schedule_test.dart' show reviewedSchedule;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> boot(WidgetTester tester, {DateTime Function()? clock}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MyApp(
        0,
        ThemeMode.light,
        '',
        scheduleLoader: () async => reviewedSchedule(),
        clock: clock ?? () => DateTime(2026, 9, 20, 14),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('tab-$name')));
    await tester.pumpAndSettle();
  }

  Finder getPageScroll(String page) => find.descendant(
    of: find.byKey(PageStorageKey('schedule-$page')),
    matching: find.byType(Scrollable),
  );

  testWidgets('today is separate and next details do not navigate away', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byType(PersonalHomeView), findsOneWidget);
    expect(find.text('日课表'), findsNWidgets(2));
    expect(find.text('9月20日 · 星期日'), findsOneWidget);
    expect(find.text('今天没有课'), findsOneWidget);
    expect(find.byTooltip('下一周'), findsNothing);
    expect(find.byTooltip('下个月'), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(
      tester
          .widget<FloatingScheduleNavigation>(
            find.byType(FloatingScheduleNavigation),
          )
          .selectedIndex,
      0,
    );
    expect(
      find.byKey(const ValueKey('tab-month')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.text('中国艺术史'));
    await tester.pumpAndSettle();
    expect(find.text('杨明刚'), findsWidgets);
    expect(find.text('周一 · 下午\n13:30–16:30'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭详情'));
    await tester.pumpAndSettle();
    expect(find.text('日课表'), findsNWidgets(2));
    expect(find.byTooltip('下一周'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'week scrolling keeps bottom tabs visible and preserves position',
    (tester) async {
      await boot(tester);
      await tab(tester, 'week');
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.text('下一节课'), findsNothing);
      expect(find.byTooltip('下个月'), findsNothing);
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      final scroll = getPageScroll('week');
      await tester.scrollUntilVisible(
        find.text('第五会议室（主校区）'),
        180,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('硕士英语(全日制学术型)'), findsOneWidget);
      expect(find.text('林敬和、刘先福'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('中国特色社会主义理论与实践研究'),
        200,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scroll).position.pixels;
      expect(offset, greaterThan(0));
      expect(
        find.byKey(const ValueKey('tab-today')).hitTestable(),
        findsOneWidget,
      );
      await tab(tester, 'today');
      expect(find.text('今天没有课'), findsOneWidget);
      expect(find.byTooltip('下一周'), findsNothing);
      await tab(tester, 'week');
      expect(tester.state<ScrollableState>(scroll).position.pixels, offset);
      await tester.scrollUntilVisible(
        find.text('第 3 周'),
        -220,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('第 3 周'), findsOneWidget);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'month dates show real courses and selected day survives tab changes',
    (tester) async {
      await boot(tester);
      await tab(tester, 'month');
      expect(find.text('2026年9月'), findsOneWidget);
      expect(find.byTooltip('下一周'), findsNothing);
      expect(find.text('下一节课'), findsNothing);
      expect(find.bySemanticsLabel('2026年9月22日 星期二，2 节课'), findsOneWidget);
      // September starts on Tuesday; its final day is Wednesday, without spillover.
      final first = tester.getCenter(
        find.byKey(const ValueKey('month-day-2026-9-1')),
      );
      final monday = tester.getCenter(
        find.byKey(const ValueKey('month-day-2026-9-7')),
      );
      expect(first.dx, greaterThan(monday.dx));
      expect(first.dy, lessThan(monday.dy));
      expect(find.byKey(const ValueKey('month-day-2026-9-31')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('month-day-2026-9-22')));
      await tester.pumpAndSettle();
      final scroll = getPageScroll('month');
      await tester.scrollUntilVisible(
        find.text('第五会议室（主校区）'),
        130,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('硕士英语(全日制学术型)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('艺术美学'),
        140,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('艺术美学'), findsOneWidget);
      await tab(tester, 'today');
      expect(find.text('9月20日 · 星期日'), findsOneWidget);
      await tab(tester, 'month');
      await tester.scrollUntilVisible(
        find.text('9月22日 · 星期二'),
        -130,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('9月22日 · 星期二'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'October keeps photography sessions and the changed English room',
    (tester) async {
      await boot(tester);
      await tab(tester, 'month');
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.bySemanticsLabel('2026年10月10日 星期六，2 节课'), findsOneWidget);
      expect(find.bySemanticsLabel('2026年10月11日 星期日，2 节课'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('month-day-2026-10-10')));
      await tester.pumpAndSettle();
      final scroll = getPageScroll('month');
      await tester.scrollUntilVisible(
        find.text('下午  13:30–16:30'),
        130,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('黑白摄影暗房工艺基础'), findsNWidgets(2));
      expect(find.text('上午  09:00–12:00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('month-day-2026-10-13')),
        -150,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-day-2026-10-13')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('6310（主校区）'),
        150,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('第五会议室（主校区）'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('本月'),
        -180,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('本月'));
      await tester.pumpAndSettle();
      expect(find.text('2026年9月'), findsOneWidget);
      expect(find.text('9月20日 · 星期日'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('month navigation crosses years and renders leap day correctly', (
    tester,
  ) async {
    await boot(tester, clock: () => DateTime(2027, 12, 31));
    await tab(tester, 'month');
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('2028年1月'), findsOneWidget);
    expect(find.text('1月1日 · 星期六'), findsOneWidget);
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('month-day-2028-2-29')), findsOneWidget);
    expect(find.byKey(const ValueKey('month-day-2028-2-30')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('month-day-2028-2-29')));
    await tester.pumpAndSettle();
    expect(find.text('2月29日 · 星期二'), findsOneWidget);
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('3月1日 · 星期三'), findsOneWidget);
    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.text('2月1日 · 星期二'), findsOneWidget);
    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();
    expect(find.text('2027年12月'), findsOneWidget);
    expect(find.text('12月31日 · 星期五'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending details are accessible from week without invented dates',
    (tester) async {
      await boot(tester);
      expect(find.text('2 门课程待安排'), findsNothing);
      await tab(tester, 'week');
      await tester.tap(find.text('2 门课程待安排'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导师课'));
      await tester.pumpAndSettle();
      expect(find.text('时间待定'), findsOneWidget);
      expect(find.text('周次待定'), findsOneWidget);
      expect(find.text('教师待定'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FloatingScheduleNavigation>(
              find.byType(FloatingScheduleNavigation),
            )
            .selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('midnight updates today and ongoing ends at the exact boundary', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 20, 23, 59);
    await boot(tester, clock: () => now);
    now = DateTime(2026, 9, 21, 13, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('9月21日 · 星期一'), findsOneWidget);
    expect(find.text('中国艺术史'), findsOneWidget);
    expect(find.text('正在上课'), findsOneWidget);
    now = DateTime(2026, 9, 21, 16, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('正在上课'), findsNothing);
    expect(find.text('已结束'), findsOneWidget);
    expect(find.text('硕士英语(全日制学术型)'), findsNothing);
    await tab(tester, 'week');
    expect(find.text('第 3 周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'gear opens settings and returns to the same month in dark mode',
    (tester) async {
      await boot(tester);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      await tab(tester, 'month');
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('手动添加课程'), findsOneWidget);
      expect(find.textContaining('捐赠'), findsNothing);
      await tester.ensureVisible(find.text('外观'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        (await SharedPreferences.getInstance()).getInt('themeModeIndex'),
        2,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('2026年10月'), findsOneWidget);
      expect(
        tester
            .widget<FloatingScheduleNavigation>(
              find.byType(FloatingScheduleNavigation),
            )
            .selectedIndex,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading failure keeps navigation and has a working retry', (
    tester,
  ) async {
    var failed = true;
    await tester.pumpWidget(
      MyApp(
        0,
        ThemeMode.light,
        '',
        scheduleLoader: () async {
          if (failed) throw StateError('read failed');
          return reviewedSchedule();
        },
        clock: () => DateTime(2026, 9, 20),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新读取'), findsOneWidget);
    expect(find.byType(FloatingScheduleNavigation), findsOneWidget);
    failed = false;
    await tester.tap(find.text('重新读取'));
    await tester.pumpAndSettle();
    expect(find.text('日课表'), findsNWidgets(2));
    expect(find.text('今天没有课'), findsOneWidget);
    expect(find.text('重新读取'), findsNothing);
  });

  testWidgets('all three pages fit a narrow screen with larger type', (
    tester,
  ) async {
    await boot(tester);
    tester.view.physicalSize = const Size(320, 740);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tab(tester, 'week');
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('中国特色社会主义理论与实践研究'),
      180,
      scrollable: getPageScroll('week'),
    );
    await tester.pumpAndSettle();
    expect(find.text('中国特色社会主义理论与实践研究'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('tab-month')).hitTestable(),
      findsOneWidget,
    );
    await tab(tester, 'month');
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    // August 2026 uses six calendar rows at this text size.
    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年8月'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('tab-today')).hitTestable(),
      findsOneWidget,
    );
    await tab(tester, 'today');
    expect(find.text('日课表'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'centered time subtitles and outlined return buttons sit by content headings',
    (tester) async {
      await boot(tester);
      await tab(tester, 'week');
      // The action remains available in an empty week.
      expect(
        find.widgetWithText(OutlinedButton, '本周').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      final weekTitle = tester.getRect(find.text('第 3 周'));
      final weekTime = tester.getRect(find.text('9/21 — 9/27'));
      final weekAction = tester.getRect(
        find.widgetWithText(OutlinedButton, '本周'),
      );
      expect(weekTime.top, greaterThan(weekTitle.bottom));
      expect(weekTime.center.dx, closeTo(weekTitle.center.dx, 1));
      expect(weekTitle.center.dx, closeTo(393 / 2, 1));
      expect(
        weekAction.center.dy,
        closeTo(tester.getCenter(find.text('9月21日  周一')).dy, 1),
      );
      expect(weekAction.right, closeTo(393 - 22, 1));
      expect(weekAction.top, greaterThan(weekTime.bottom));
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      await tab(tester, 'month');
      final monthTitle = tester.getRect(find.text('2026年9月'));
      final monthSubtitle = tester.getRect(find.text('12 节课'));
      final monthAction = tester.getRect(
        find.widgetWithText(OutlinedButton, '本月'),
      );
      expect(monthSubtitle.top, greaterThan(monthTitle.bottom));
      expect(monthSubtitle.center.dx, closeTo(monthTitle.center.dx, 1));
      expect(
        monthAction.center.dy,
        closeTo(tester.getCenter(find.text('9月20日 · 星期日')).dy, 1),
      );
      expect(monthAction.right, closeTo(weekAction.right, 1));
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本月'));
      await tester.pumpAndSettle();
      expect(find.text('2026年9月'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('floating lens moves continuously and respects reduced motion', (
    tester,
  ) async {
    await boot(tester);
    final indicator = find.byKey(const ValueKey('floating-tab-indicator'));
    final bar = tester.getRect(
      find.byKey(const ValueKey('floating-schedule-bar')),
    );
    final start = tester.getCenter(indicator).dx;
    await tester.tap(find.byKey(const ValueKey('tab-month')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final during = tester.getCenter(indicator).dx;
    await tester.pumpAndSettle();
    final end = tester.getCenter(indicator).dx;
    expect(during, greaterThan(start));
    expect(during, lessThan(end));
    expect(
      end,
      closeTo(tester.getCenter(find.byKey(const ValueKey('tab-month'))).dx, 1),
    );
    expect(bar.left, greaterThan(0));
    expect(bar.right, lessThan(393));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('tab-month')))
          .flagsCollection
          .isSelected,
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('tab-today')))
          .flagsCollection
          .isSelected,
      isFalse,
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-today')));
    await tester.pump();
    expect(tester.getCenter(indicator).dx, closeTo(start, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'last course and pending details can scroll above the floating bar',
    (tester) async {
      await boot(tester);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      await tester.pumpAndSettle();
      await tab(tester, 'week');
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      final scroll = getPageScroll('week');
      final barFinder = find.byKey(const ValueKey('floating-schedule-bar'));
      final fixedBar = tester.getRect(barFinder);
      await tester.drag(scroll, const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(tester.getRect(barFinder), fixedBar);
      expect(find.text('2 门课程待安排').hitTestable(), findsOneWidget);
      await tester.tap(find.text('2 门课程待安排'));
      await tester.pumpAndSettle();
      await tester.drag(scroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('导师课')).bottom, lessThan(fixedBar.top));
      expect(fixedBar.bottom, lessThanOrEqualTo(852 - 34));
      await tester.tap(find.text('导师课'));
      await tester.pumpAndSettle();
      expect(find.text('时间待定'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tab-month')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
