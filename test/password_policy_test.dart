import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('rejects empty password', () {
      final result = PasswordPolicy.validate(
        password: '',
        confirmPassword: '',
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, equals('Password cannot be empty.'));
    });

    test('rejects password shorter than 8 characters', () {
      final result = PasswordPolicy.validate(
        password: '1234567',
        confirmPassword: '1234567',
      );
      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        equals('Password must be at least 8 characters long.'),
      );
    });

    test('rejects password with newline characters', () {
      final resultLf = PasswordPolicy.validate(
        password: 'pass\nword123',
        confirmPassword: 'pass\nword123',
      );
      expect(resultLf.isValid, isFalse);
      expect(
        resultLf.errorMessage,
        equals('Password cannot contain newline characters.'),
      );

      final resultCr = PasswordPolicy.validate(
        password: 'pass\rword123',
        confirmPassword: 'pass\rword123',
      );
      expect(resultCr.isValid, isFalse);
      expect(
        resultCr.errorMessage,
        equals('Password cannot contain newline characters.'),
      );
    });

    test('rejects password with NUL character', () {
      final result = PasswordPolicy.validate(
        password: 'password\u0000123',
        confirmPassword: 'password\u0000123',
      );
      expect(result.isValid, isFalse);
      expect(
        result.errorMessage,
        equals('Password cannot contain NUL characters.'),
      );
    });

    test('rejects password and confirmation mismatch', () {
      final result = PasswordPolicy.validate(
        password: 'correct_horse_battery',
        confirmPassword: 'staple_horse_battery',
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, equals('Passwords do not match.'));
    });

    test('accepts valid passwords (minimum 8 chars, unicode, symbols, long)', () {
      final result1 = PasswordPolicy.validate(
        password: '12345678',
        confirmPassword: '12345678',
      );
      expect(result1.isValid, isTrue);
      expect(result1.errorMessage, isNull);

      final resultUnicode = PasswordPolicy.validate(
        password: 'Tést Pass ફા 123!',
        confirmPassword: 'Tést Pass ફા 123!',
      );
      expect(resultUnicode.isValid, isTrue);

      final resultLong = PasswordPolicy.validate(
        password: 'A' * 200,
        confirmPassword: 'A' * 200,
      );
      expect(resultLong.isValid, isTrue);
    });
  });
}
