/// Display-only stand-in for a secret that stays in secure storage.
class SecretMask {
  static const placeholder = '••••••••';

  /// A long key keeps a short head and tail so the field looks filled.
  /// Short values stay fully hidden.
  static String apiKey(String raw) {
    final value = raw.trim();
    if (value.length <= 8) return placeholder;
    return '${value.substring(0, 3)}••••${value.substring(value.length - 4)}';
  }
}
