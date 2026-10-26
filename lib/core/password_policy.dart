import 'dart:core';

class PasswordValidationResult {
  final bool isValid;
  final String? errorMessage;

  const PasswordValidationResult.valid() : isValid = true, errorMessage = null;

  const PasswordValidationResult.invalid(this.errorMessage) : isValid = false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PasswordValidationResult &&
          runtimeType == other.runtimeType &&
          isValid == other.isValid &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(isValid, errorMessage);

  @override
  String toString() => isValid
      ? 'PasswordValidationResult.valid'
      : 'PasswordValidationResult.invalid($errorMessage)';
}

class PasswordPolicy {
  static const int minLength = 8;

  static PasswordValidationResult validate({
    required String password,
    required String confirmPassword,
  }) {
    if (password.isEmpty) {
      return const PasswordValidationResult.invalid(
        'Password cannot be empty.',
      );
    }
    if (password.length < minLength) {
      return const PasswordValidationResult.invalid(
        'Password must be at least 8 characters long.',
      );
    }
    if (password.contains('\n') || password.contains('\r')) {
      return const PasswordValidationResult.invalid(
        'Password cannot contain newline characters.',
      );
    }
    if (password.contains('\u0000')) {
      return const PasswordValidationResult.invalid(
        'Password cannot contain NUL characters.',
      );
    }
    if (password != confirmPassword) {
      return const PasswordValidationResult.invalid('Passwords do not match.');
    }
    return const PasswordValidationResult.valid();
  }
}
