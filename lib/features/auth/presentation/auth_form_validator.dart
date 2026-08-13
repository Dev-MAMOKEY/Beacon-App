/// 정규식은 Swagger 스키마를 정본으로 삼는다.
/// 서버가 최종 판정을 하고, 여기서는 왕복을 줄이기 위해 미리 걸러낸다.
abstract final class AuthFormValidator {
  static final RegExp _stdId = RegExp(r'^[A-Za-z0-9]{4,20}$');
  static final RegExp _passwordShape = RegExp(r'^(?=.*[A-Za-z])(?=.*\d).+$');
  static final RegExp _name = RegExp(r'^[가-힣a-zA-Z]{2,20}$');

  static String? stdId(String value) {
    if (value.isEmpty) return '학번을 입력해주세요';
    if (!_stdId.hasMatch(value)) return '학번은 영문/숫자 4~20자여야 합니다';
    return null;
  }

  static String? password(String value) {
    if (value.isEmpty) return '비밀번호를 입력해주세요';
    if (value.length < 8) return '비밀번호는 8자 이상이어야 합니다';
    if (!_passwordShape.hasMatch(value)) return '영문과 숫자를 모두 포함해야 합니다';
    return null;
  }

  static String? passwordConfirm(String password, String confirm) {
    if (confirm.isEmpty) return '비밀번호를 한 번 더 입력해주세요';
    if (password != confirm) return '비밀번호가 일치하지 않습니다';
    return null;
  }

  static String? name(String value) {
    if (value.isEmpty) return '이름을 입력해주세요';
    if (!_name.hasMatch(value)) return '이름은 한글 또는 영문 2~20자여야 합니다';
    return null;
  }
}
