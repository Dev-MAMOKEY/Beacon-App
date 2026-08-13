import 'package:beacon_app/features/auth/presentation/auth_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stdId', () {
    test('4~20자 영숫자를 허용한다', () {
      expect(AuthFormValidator.stdId('20250101'), isNull);
      expect(AuthFormValidator.stdId('abc1'), isNull);
    });

    test('3자 이하나 특수문자를 거부한다', () {
      expect(AuthFormValidator.stdId('abc'), isNotNull);
      expect(AuthFormValidator.stdId('2025-0101'), isNotNull);
      expect(AuthFormValidator.stdId(''), isNotNull);
    });
  });

  group('password', () {
    test('8자 이상이며 영문과 숫자를 모두 포함하면 통과한다', () {
      expect(AuthFormValidator.password('abcd1234'), isNull);
    });

    test('7자 이하, 숫자 없음, 영문 없음을 각각 거부한다', () {
      expect(AuthFormValidator.password('abc1234'), isNotNull);
      expect(AuthFormValidator.password('abcdefgh'), isNotNull);
      expect(AuthFormValidator.password('12345678'), isNotNull);
    });
  });

  group('name', () {
    test('2~20자 한글 또는 영문을 허용한다', () {
      expect(AuthFormValidator.name('김민준'), isNull);
      expect(AuthFormValidator.name('Minjun'), isNull);
    });

    test('1자, 숫자 포함, 공백 포함을 거부한다', () {
      expect(AuthFormValidator.name('김'), isNotNull);
      expect(AuthFormValidator.name('김민준2'), isNotNull);
      expect(AuthFormValidator.name('김 민준'), isNotNull);
    });
  });

  group('passwordConfirm', () {
    test('일치하면 null, 다르면 메시지', () {
      expect(AuthFormValidator.passwordConfirm('abcd1234', 'abcd1234'), isNull);
      expect(AuthFormValidator.passwordConfirm('abcd1234', 'abcd12345'), isNotNull);
    });
  });
}
