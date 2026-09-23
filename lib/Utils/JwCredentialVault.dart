import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ScheduleDerivedDataService.dart';

class JwCredentials {
  final String username;
  final String password;

  const JwCredentials(this.username, this.password);
}

/// Legacy JW “remember password” store.
///
/// The password is written to the platform Keychain / Keystore item used by
/// [ScheduleCredentialsStore]. The old SharedPreferences password and username
/// are removed only after that write succeeds.
class JwCredentialVault {
  static const passwordKey = 'password';
  static const usernameKey = 'username';

  final Future<JwCredentials?> Function() readSecure;
  final Future<void> Function(String username, String password) writeSecure;
  final Future<void> Function() deleteSecure;
  final String? Function() readLegacyPassword;
  final String? Function() readLegacyUsername;
  final Future<void> Function() removeLegacyPassword;
  final Future<void> Function() removeLegacyUsername;

  JwCredentialVault({
    required this.readSecure,
    required this.writeSecure,
    required this.deleteSecure,
    required this.readLegacyPassword,
    required this.readLegacyUsername,
    required this.removeLegacyPassword,
    required this.removeLegacyUsername,
  });

  static JwCredentialVault platform() {
    const channel = ScheduleDerivedDataService.channel;
    return JwCredentialVault(
      readSecure: () => _readChannel(channel),
      writeSecure: (username, password) async {
        await channel.invokeMethod('saveLegacyJwCredentials', {
          'username': username,
          'password': password,
        });
      },
      deleteSecure: () async {
        await channel.invokeMethod('deleteLegacyJwCredentials');
      },
      readLegacyPassword: _prefsPassword,
      readLegacyUsername: _prefsUsername,
      removeLegacyPassword: _removePrefsPassword,
      removeLegacyUsername: _removePrefsUsername,
    );
  }

  static Future<JwCredentials?> _readChannel(MethodChannel channel) async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'loadLegacyJwCredentials',
    );
    if (value == null) return null;
    final username = (value['username'] as String? ?? '').trim();
    final password = value['password'] as String? ?? '';
    if (username.isEmpty || password.isEmpty) return null;
    return JwCredentials(username, password);
  }

  static String? _prefsPassword() => _cachedPrefs?.getString(passwordKey);

  static String? _prefsUsername() => _cachedPrefs?.getString(usernameKey);

  static SharedPreferences? _cachedPrefs;

  static Future<SharedPreferences> _prefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> _removePrefsPassword() async {
    final prefs = await _prefs();
    await prefs.remove(passwordKey);
  }

  static Future<void> _removePrefsUsername() async {
    final prefs = await _prefs();
    await prefs.remove(usernameKey);
  }

  /// Binds the legacy readers to an already loaded preferences instance.
  /// Tests use this so migration does not depend on the platform channel.
  factory JwCredentialVault.forPreferences(
    SharedPreferences prefs, {
    required Future<JwCredentials?> Function() readSecure,
    required Future<void> Function(String username, String password) writeSecure,
    required Future<void> Function() deleteSecure,
  }) {
    return JwCredentialVault(
      readSecure: readSecure,
      writeSecure: writeSecure,
      deleteSecure: deleteSecure,
      readLegacyPassword: () => prefs.getString(passwordKey),
      readLegacyUsername: () => prefs.getString(usernameKey),
      removeLegacyPassword: () => prefs.remove(passwordKey),
      removeLegacyUsername: () => prefs.remove(usernameKey),
    );
  }

  Future<JwCredentials?> load() async {
    if (readLegacyPassword == _prefsPassword) await _prefs();
    final secure = await readSecure();
    final legacyPassword = readLegacyPassword();
    final legacyUsername = readLegacyUsername()?.trim();
    if (secure == null &&
        legacyPassword != null &&
        legacyPassword.isNotEmpty &&
        legacyUsername != null &&
        legacyUsername.isNotEmpty) {
      await writeSecure(legacyUsername, legacyPassword);
      await removeLegacyPassword();
      await removeLegacyUsername();
      return JwCredentials(legacyUsername, legacyPassword);
    }
    if (legacyPassword != null) {
      await removeLegacyPassword();
    }
    if (secure != null) {
      await removeLegacyUsername();
    }
    return secure;
  }

  Future<void> save(String username, String password) async {
    final account = username.trim();
    if (account.isEmpty || password.isEmpty) {
      throw ArgumentError('账号和密码不能为空');
    }
    await writeSecure(account, password);
    await removeLegacyPassword();
    await removeLegacyUsername();
  }

  Future<void> delete() async {
    await deleteSecure();
    await removeLegacyPassword();
    await removeLegacyUsername();
  }
}
