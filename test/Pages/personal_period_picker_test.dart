import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosleepinnju/generated/l10n.dart';
import 'package:wheretosleepinnju/Pages/AddCourse/Widgets/WeekTimeNodeDialog.dart';

void main() {
  testWidgets(
    'manual course time uses three imported periods and saves a valid evening range',
    (tester) async {
      const periods = [
        {'label': '上午', 'start': '09:00', 'end': '12:00'},
        {'label': '下午', 'start': '13:30', 'end': '16:30'},
        {'label': '晚上', 'start': '19:00', 'end': '21:30'},
      ];
      final original = {'weekTime': 0, 'startTime': 0, 'endTime': 0};
      Map? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: S.delegate.supportedLocales,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<Map>(
                    context: context,
                    builder: (_) =>
                        WeekTimeNodeDialog(node: original, periods: periods),
                  );
                },
                child: const Text('选择时间'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择时间'));
      await tester.pumpAndSettle();
      final pickers = tester
          .widgetList<CupertinoPicker>(find.byType(CupertinoPicker))
          .toList();
      expect(pickers, hasLength(3));
      pickers[1].scrollController!.jumpToItem(2);
      await tester.pumpAndSettle();
      expect(pickers[2].scrollController!.selectedItem, 2);
      expect(find.text('第13节'), findsNothing);
      expect(original['startTime'], 0);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(result, {'weekTime': 0, 'startTime': 2, 'endTime': 2});
      expect(tester.takeException(), isNull);
    },
  );
}
