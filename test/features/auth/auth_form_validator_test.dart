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

    test('경계값: 20자는 허용하고 21자는 거부한다', () {
      // 상한을 8자 등 다른 값으로 잘못 캡핑한 구현도 '4~20자를 허용한다'는
      // 기존 테스트만으로는 걸러지지 않는다 — 정확한 경계를 직접 찍는다.
      expect(AuthFormValidator.stdId('12345678901234567890'), isNull); // 20자
      expect(AuthFormValidator.stdId('123456789012345678901'), isNotNull); // 21자
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

    test('경계값: 정확히 8자와 9자 모두 통과한다', () {
      // "정확히 8자"만 통과시키는(그 이상은 거부하는) 잘못된 구현도
      // '8자 이상' 테스트 하나만으로는 걸러지지 않는다.
      expect(AuthFormValidator.password('abcd1234'), isNull); // 정확히 8자
      expect(AuthFormValidator.password('abcd12345'), isNull); // 9자
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

    test('경계값: 2자와 20자는 허용하고 21자는 거부한다', () {
      // 좁은 범위(예: 3~6자)만 허용하는 잘못된 구현도 '2~20자를 허용한다'는
      // 기존 테스트(3자짜리 예시들)만으로는 걸러지지 않는다.
      expect(AuthFormValidator.name('Ab'), isNull); // 2자
      expect(AuthFormValidator.name('abcdefghijklmnopqrst'), isNull); // 20자
      expect(AuthFormValidator.name('abcdefghijklmnopqrstu'), isNotNull); // 21자
    });
  });

  group('passwordConfirm', () {
    test('일치하면 null, 다르면 메시지', () {
      expect(AuthFormValidator.passwordConfirm('abcd1234', 'abcd1234'), isNull);
      expect(AuthFormValidator.passwordConfirm('abcd1234', 'abcd12345'), isNotNull);
    });

    test('길이가 같아도 내용이 다르면 거부한다', () {
      // password.length == confirm.length로 길이만 비교하는 잘못된 구현은
      // 위 두 케이스(길이가 서로 다름)만으로는 걸러지지 않는다 — 길이는
      // 같지만 마지막 한 글자만 다른 경우로 내용 자체를 비교하는지 확인한다.
      expect(AuthFormValidator.passwordConfirm('abcd1234', 'abcd1235'), isNotNull);
    });
  });
}
