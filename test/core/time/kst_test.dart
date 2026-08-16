import 'package:beacon_app/core/time/kst.dart';
import 'package:flutter_test/flutter_test.dart';

/// `toKst` 자체를 **기계 시간대와 무관하게** 고정한다.
///
/// 이 파일이 필요한 이유: 이 프로젝트의 개발 기계는 KST라, `toKst`를
/// `value.toLocal()`로 바꿔도 기록 화면 테스트 15개가 전부 초록이었다. 깨지는
/// 것은 `TZ=UTC`로 돌릴 때뿐이다 — **수정을 작성한 기계에서는 두 구현이
/// 구별되지 않았다**(리뷰 Minor 1). 아래 검사들은 어느 시간대에서 돌려도
/// 같은 결과를 낸다.
void main() {
  test('toKst는 기기 시간대와 무관하게 항상 UTC+9로 옮긴다', () {
    // 잡아야 할 잘못된 구현: `value.toLocal()`.
    //
    // `toLocal()`이 돌려주는 값은 원본과 **같은 순간**이라 `difference`가 0이다
    // (`DateTime.difference`는 isUtc 플래그가 아니라 epoch 값을 뺀다). 반면
    // `toKst`가 돌려주는 값은 "읽기 전용 KST 벽시계"라 원본보다 정확히 9시간
    // 뒤의 순간으로 표현된다. 이 차이는 기계 시간대가 무엇이든 성립한다 —
    // KST 기계에서도 `toLocal()`을 잡아낸다.
    final utcInstant = DateTime.utc(2026, 8, 8, 16);
    expect(toKst(utcInstant).difference(utcInstant), kstOffset);

    // 입력이 로컬 시각이어도 같은 규칙이다(`DateTime.now()`가 이 경우다).
    final localInstant = DateTime(2026, 8, 8, 16);
    expect(toKst(localInstant).difference(localInstant), kstOffset);
  });

  test('toKst가 돌려준 값의 벽시계 필드가 KST다', () {
    // 잡아야 할 잘못된 구현: `.toUtc()` 없이 벽시계에 9시간을 더한다 — 입력이
    // 이미 로컬(UTC+9가 아닌) 시각이면 엉뚱한 시각이 나온다.
    final kst = toKst(DateTime.utc(2026, 8, 8, 16, 30));
    expect(
      (kst.year, kst.month, kst.day, kst.hour, kst.minute),
      (2026, 8, 9, 1, 30),
    );
  });

  test('toKst는 날짜·달·해 넘김까지 함께 넘긴다', () {
    // 잡아야 할 잘못된 구현: 시(hour)에만 9를 더하고 자정을 넘길 때 날짜를
    // 올리지 않는다.
    final newYear = toKst(DateTime.utc(2025, 12, 31, 15));
    expect((newYear.year, newYear.month, newYear.day, newYear.hour), (2026, 1, 1, 0));

    // 기록 화면의 월 경계가 정확히 이 계산 위에 서 있다.
    final monthEnd = toKst(DateTime.utc(2026, 8, 31, 22));
    expect((monthEnd.year, monthEnd.month, monthEnd.day, monthEnd.hour), (2026, 9, 1, 7));
  });

  test('kstOffset은 계절과 무관하게 9시간이다', () {
    // 한국에는 서머타임이 없다 — 시간대 데이터베이스 없이 +9를 상수로 둘 수
    // 있는 근거이므로 겨울·여름 양쪽을 실제로 태운다.
    expect(kstOffset, const Duration(hours: 9));
    expect(toKst(DateTime.utc(2026, 1, 15, 3)).hour, 12);
    expect(toKst(DateTime.utc(2026, 7, 15, 3)).hour, 12);
  });
}
