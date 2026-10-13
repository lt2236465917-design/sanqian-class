import 'package:flutter_test/flutter_test.dart';
import 'package:sanqian_class/Utils/SecretMask.dart';

void main() {
  test('api key mask keeps a short head and tail', () {
    expect(SecretMask.apiKey('sk-1234567890abcd'), 'sk-••••abcd');
    expect(SecretMask.apiKey('  fixture-key  '), 'fix••••-key');
  });

  test('short secrets stay fully hidden', () {
    expect(SecretMask.apiKey('short'), SecretMask.placeholder);
    expect(SecretMask.apiKey('12345678'), SecretMask.placeholder);
  });
}
