/// 서버는 모든 시각을 UTC(ISO 8601, 끝에 `Z`)로 내려주고, `DateTime.parse`는
/// 그것을 `isUtc: true`인 [DateTime]으로 만든다. 그 값의 `.hour`/`.day`를
/// 그대로 읽으면 **UTC 벽시계**가 나온다 — 화면에는 KST로 보여야 한다.
/// (이슈 #12 "UTC → KST 변환은 표현 계층에서 처리".)
const Duration kstOffset = Duration(hours: 9);

/// [value]를 KST 벽시계로 옮긴다. 반환값의 `isUtc` 플래그에는 의미가 없다 —
/// `.year`/`.month`/`.day`/`.hour`/`.minute`로 **읽기만** 하는 용도다.
/// 이 값을 다시 서버로 보내거나 다른 시각과 비교해서는 안 된다.
///
/// `toLocal()`을 쓰지 않는 이유 세 가지.
/// 1. 명세가 요구하는 것은 "기기 시간대"가 아니라 KST다 — 동아리 세션은
///    한국 시각으로 열리므로, 사용자가 해외에 있어도 KST로 보여야 맞다.
/// 2. `toLocal()`은 테스트를 실행하는 기계의 시간대에 따라 결과가 달라져서
///    "KST로 표시된다"를 고정하는 테스트를 아예 쓸 수 없다(CI는 보통 UTC다).
/// 3. 한국은 서머타임이 없어 +9가 연중 정확하다 — 시간대 데이터베이스가
///    필요 없다.
DateTime toKst(DateTime value) => value.toUtc().add(kstOffset);
