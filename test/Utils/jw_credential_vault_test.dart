import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wheretosleepinnju/Pages/Import/ImportFromJWPresenter.dart';
import 'package:wheretosleepinnju/Pages/Import/ImportFromJWView.dart';
import 'package:wheretosleepinnju/Utils/JwCredentialVault.dart';
import 'package:wheretosleepinnju/generated/l10n.dart';

class _QuietCaptcha extends ImportFromJWPresenter {
  @override
  Future<Image> getCaptcha(double num) async {
    return Image.memory(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({JwCredentialVault vault, Map<String, String> secure, SharedPreferences prefs})>
  vaultWith({String? username, String? password, Map<String, String>? existing}) async {
    SharedPreferences.setMockInitialValues({
      if (username != null) 'username': username,
      if (password != null) 'password': password,
    });
    final prefs = await SharedPreferences.getInstance();
    final secure = {...?existing};
    final vault = JwCredentialVault.forPreferences(
      prefs,
      readSecure: () async {
        final account = secure['username'];
        final secret = secure['password'];
        if (account == null || secret == null || account.isEmpty || secret.isEmpty) {
          return null;
        }
        return JwCredentials(account, secret);
      },
      writeSecure: (account, secret) async {
        secure['username'] = account;
        secure['password'] = secret;
      },
      deleteSecure: () async => secure.clear(),
    );
    return (vault: vault, secure: secure, prefs: prefs);
  }

  test('migration copies the plaintext password once and deletes the old key', () async {
    final harness = await vaultWith(username: '20210001', password: 'secret-jw');
    final loaded = await harness.vault.load();
    expect(loaded!.username, '20210001');
    expect(loaded.password, 'secret-jw');
    expect(harness.prefs.getString('password'), isNull);
    expect(harness.prefs.getString('username'), isNull);
    expect(harness.prefs.containsKey('password'), isFalse);
    expect(harness.secure['password'], 'secret-jw');

    harness.secure['password'] = 'newer-secret';
    await harness.prefs.setString('password', 'stale-secret');
    await harness.prefs.setString('username', '20210001');
    final again = await harness.vault.load();
    expect(again!.username, '20210001');
    expect(again.password, 'newer-secret');
    expect(harness.secure['password'], 'newer-secret');
    expect(harness.prefs.getString('password'), isNull);
    expect(harness.prefs.getString('username'), isNull);
  });

  test('save and delete leave no plaintext password', () async {
    final harness = await vaultWith();
    await harness.vault.save('20210002', 'remembered');
    expect(harness.prefs.getString('password'), isNull);
    expect(harness.secure['password'], 'remembered');
    await harness.prefs.setString('password', 'should-disappear');
    await harness.vault.delete();
    expect(harness.secure, isEmpty);
    expect(harness.prefs.getString('password'), isNull);
    expect(harness.prefs.getString('username'), isNull);
  });

  test('failed secure write keeps the old plaintext password', () async {
    SharedPreferences.setMockInitialValues({
      'username': '20210001',
      'password': 'secret-jw',
    });
    final prefs = await SharedPreferences.getInstance();
    final vault = JwCredentialVault.forPreferences(
      prefs,
      readSecure: () async => null,
      writeSecure: (_, __) async => throw StateError('keystore'),
      deleteSecure: () async {},
    );
    await expectLater(vault.load(), throwsStateError);
    expect(prefs.getString('password'), 'secret-jw');
    expect(prefs.getString('username'), '20210001');
  });

  testWidgets('remembered password fills the form and unchecking deletes it', (
    tester,
  ) async {
    final harness = await vaultWith(username: '20210001', password: 'secret-jw');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: ImportFromJWView(
          credentials: harness.vault,
          presenter: _QuietCaptcha(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, '20210001');
    expect(fields[1].controller?.text, 'secret-jw');
    expect(harness.prefs.getString('password'), isNull);
    expect(harness.prefs.getString('username'), isNull);
    expect(harness.secure['password'], 'secret-jw');

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.pump();
    expect(harness.secure, isEmpty);
    expect(harness.prefs.getString('password'), isNull);
    expect(harness.prefs.getString('username'), isNull);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });
}
