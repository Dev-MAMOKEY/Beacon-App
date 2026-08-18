import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/error_code.dart';
import '../../../core/storage/token_write_coordinator.dart';
import '../data/auth_dto.dart';
import '../data/auth_repository.dart';

sealed class SessionState {
  const SessionState();
}

class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// 로그인은 됐지만 동아리 소속이 없다. 초대코드 화면으로 보낸다.
class SessionNeedsClub extends SessionState {
  const SessionNeedsClub(this.profile);

  final MemberProfile profile;
}

class SessionReady extends SessionState {
  const SessionReady(this.profile);

  final MemberProfile profile;

  int get clubId => profile.primaryClubId;
}

/// 세션을 판별하지 못했다. 자격 증명이 무효라는 뜻은 아니므로 토큰을 지우지
/// 않는다 — 오프라인이거나 서버가 일시적으로 5xx를 낸 경우가 이 상태다.
/// 스플래시가 재시도 UI를 보여준다.
class SessionUnavailable extends SessionState {
  const SessionUnavailable(this.message);

  final String message;
}

// 자격-증명-죽음 판정은 core/network/error_code.dart의 isAuthFailure가
// 정본이다. AuthInterceptor도 그 함수를 그대로 부른다 — 집합만 공유하고
// 판정 로직은 각자 갖고 있다가 서로 다르게 굴게 되는 것이 실제 버그의
// 근원이었으므로, 이 파일에는 집합도 판정도 두지 않는다.

class SessionController extends AsyncNotifier<SessionState> {
  /// 진행 중인 판별(_resolve)이나 커맨드(onAuthenticated/refreshProfile/
  /// signOut)가 여러 개 겹칠 때 어느 것이 최신인지 가리는 세대 번호와, 토큰
  /// 쓰기를 직렬화하는 큐는 [TokenWriteCoordinator]가 갖고 있다. 여기 두지
  /// 않는 이유는 AuthInterceptor도 같은 카운터와 같은 큐를 써야 하기
  /// 때문이다 — 인터셉터가 저장소에 직접 쓰던 시절에는 로그아웃과 재발급이
  /// 겹치면 로그아웃 뒤에 회전된 토큰이 저장되는 일이 실제로 가능했다.
  ///
  /// build()가 다시 호출되는 것(초기 진입, sessionExpiredProvider 증가,
  /// 재시도용 invalidate)도 세대에 포함된다 — Riverpod는 build()가 새로
  /// 시작되면 이전 build()의 *상태 반영*은 알아서 버리지만, 이미 시작된
  /// 부수효과(토큰 저장/삭제)까지 취소해주지는 않으므로 그 부분은 세대로
  /// 직접 막는다.
  ///
  /// 정확히 보장되는 것: 낡은 커맨드는 저장소에도 쓰지 않고([_publish]가
  /// 아무것도 하지 않으므로) 상태도 건드리지 않는다. 유일한 예외는 build()의
  /// **반환값**인데, 그건 Riverpod가 대신 대입하므로 우리가 "아무것도 하지
  /// 않기"를 고를 수 없다 — 그래서 [_settle]이 지금 상태를 그대로 되돌려
  /// 현상 유지시킨다.
  TokenWriteCoordinator get _tokens => ref.read(tokenWriteCoordinatorProvider);

  @override
  Future<SessionState> build() async {
    // 인터셉터가 재발급에 실패하면 이 값이 증가한다. 그때 다시 판별한다.
    ref.watch(sessionExpiredProvider);
    return _resolve();
  }

  Future<SessionState> _resolve() async {
    final generation = _tokens.beginOperation();

    final String? refreshToken;
    try {
      refreshToken = await _tokens.readRefreshToken();
    } catch (_) {
      // 키체인/키스토어 접근 자체가 깨진 경우. 자격 증명이 무효라고 단정할
      // 근거가 없으므로 토큰을 건드리지 않는다.
      return _settle(generation, const SessionUnavailable('저장된 로그인 정보를 읽지 못했습니다.'));
    }
    if (refreshToken == null) {
      return _settle(generation, const SessionSignedOut());
    }

    final repository = ref.read(authRepositoryProvider);
    try {
      final tokens = await repository.refresh(refreshToken);

      // 이 flight가 대기하는 동안 다른 커맨드가 이미 상태를 바꿨다면, 방금
      // 받은 토큰은 낡은 것일 수 있다 — 빠른 경로로 미리 걸러 불필요한
      // 큐 진입/토큰 재조회를 피한다. 최종 방어선은 여전히 큐 안의 세대
      // 재확인이다.
      if (generation != _tokens.generation) return _current();

      await _writeTokens(
        generation,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );

      final profile = await repository.fetchMe();
      final resolved = profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
      return _settle(generation, resolved);
    } on ApiException catch (error) {
      if (isAuthFailure(code: error.code, statusCode: error.statusCode)) {
        try {
          await _clearTokens(generation);
        } catch (_) {
          // 스토어 정리 실패는 무시한다 — 어차피 SignedOut으로 보고한다.
        }
        return _settle(generation, const SessionSignedOut());
      }
      // 네트워크 단절이나 서버 오류(5xx)는 자격 증명이 무효라는 뜻이
      // 아니다. 토큰은 그대로 두고 재시도 가능한 상태로만 알린다.
      return _settle(generation, SessionUnavailable(error.message));
    } catch (_) {
      return _settle(generation, const SessionUnavailable('세션을 확인하지 못했습니다.'));
    }
  }

  /// 로그인/회원가입 성공 직후 호출한다.
  Future<void> onAuthenticated(TokenResponse tokens) async {
    final generation = _tokens.beginOperation();
    state = const AsyncValue.loading();

    SessionState result;
    try {
      await _writeTokens(
        generation,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      // 저장을 기다리는 사이 더 최신 커맨드가 시작됐다면 이 로그인 결과는
      // 이미 남의 것이다 — 상태를 건드리지 않고 그대로 빠진다.
      if (generation != _tokens.generation) return;

      final profile = await ref.read(authRepositoryProvider).fetchMe();
      // 토큰 저장은 이미 끝났다 — 프로필 조회 실패만으로 로그아웃 취급하지
      // 않는다. 유효한 자격 증명이 스토리지에 남아 있는데 로그인 화면으로
      // 돌려보내는 건 잘못된 결과다.
      result = profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
    } on ApiException catch (error) {
      // 예전엔 방금 로그인했다는 이유로 fetchMe의 인증 오류도 분류하지 않고
      // 전부 SessionUnavailable로 보냈다("판단이 모호하다"는 이유였다).
      // 하지만 여기서 도달 가능한 인증-실패 코드는 전부 재시도로 복구되지
      // 않는다 — 방금 발급된 토큰이 TOKEN_EXPIRED일 리 없고, TOKEN_INVALID/
      // TOKEN_MISSING은 클라이언트 버그를 뜻하며, MEMBER_NOT_FOUND는 계정
      // 자체가 없다는 뜻이다. 재시도 화면에 가두는 대신 _resolve()와 같은
      // 분류를 적용해 SignedOut으로 보내고 다시 로그인하게 한다 — 최악의
      // 경우도 재입력 한 번일 뿐, 복구 불가능한 재시도 화면보다는 낫다.
      if (isAuthFailure(code: error.code, statusCode: error.statusCode)) {
        try {
          await _clearTokens(generation);
        } catch (_) {
          // 스토어 정리 실패는 무시한다 — 어차피 SignedOut으로 보고한다.
        }
        result = const SessionSignedOut();
      } else {
        result = SessionUnavailable(error.message);
      }
    } catch (_) {
      result = const SessionUnavailable('로그인 정보를 저장하지 못했습니다.');
    }

    _publish(generation, result);
  }

  /// 초대코드 가입 성공 직후 호출한다.
  Future<void> refreshProfile() async {
    final generation = _tokens.beginOperation();

    SessionState result;
    try {
      final profile = await ref.read(authRepositoryProvider).fetchMe();
      result = profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
    } on ApiException catch (error) {
      if (isAuthFailure(code: error.code, statusCode: error.statusCode)) {
        // _resolve()와 동일한 분류를 적용한다 — 이미 로그인된 사용자의
        // 토큰이 그 사이 만료/폐기됐다는 뜻이므로 재시도 화면이 아니라
        // 로그인 화면으로 보내야 한다.
        try {
          await _clearTokens(generation);
        } catch (_) {
          // 스토어 정리 실패는 무시한다 — 어차피 SignedOut으로 보고한다.
        }
        result = const SessionSignedOut();
      } else {
        result = SessionUnavailable(error.message);
      }
    } catch (_) {
      result = const SessionUnavailable('프로필을 다시 불러오지 못했습니다.');
    }

    _publish(generation, result);
  }

  /// 이 기기에서 **서버가 이미 200으로 확정한** 프로필 수정을 세션 상태에
  /// 반영한다. 네트워크를 타지 않는다.
  ///
  /// [refreshProfile]을 쓰지 않는 이유: 그건 `GET /members/me`를 다시 타고,
  /// 그 조회가 실패하면 세션을 [SessionUnavailable]로 떨어뜨린다 —
  /// `computeRedirect`가 그 상태를 스플래시(재시도 화면)로 보내므로, 알림
  /// 토글 한 번이나 이름 한 줄 수정이 그 직후 네트워크가 잠깐 흔들렸다는
  /// 이유만으로 사용자를 화면 밖으로 튕겨낸다. 초대코드 가입처럼 "새로
  /// 조회해야만 알 수 있는 것"(clubIds)이 걸린 경우가 아니면 이쪽을 쓴다.
  ///
  /// 세대(`_tokens.generation`)를 보지 않는 대신 **현재 상태**를 본다.
  /// [SessionSignedOut]/[SessionUnavailable]에는 갈아끼울 프로필 자체가
  /// 없으므로 아무것도 하지 않는다 — 로그아웃이 먼저 반영된 뒤에 도착한
  /// 수정 결과가 죽은 세션을 되살리는 일을 여기서 막는다.
  void applyProfileChange({String? name, bool? pushEnabled}) {
    final current = state.value;
    if (current == null) return;

    // 봉인된 SessionState 위의 exhaustive switch — 프로필을 든 상태가
    // 하나 더 생기면 컴파일 타임에 누락을 알려준다.
    final SessionState? next = switch (current) {
      SessionReady(:final profile) =>
        SessionReady(profile.copyWith(name: name, pushEnabled: pushEnabled)),
      SessionNeedsClub(:final profile) =>
        SessionNeedsClub(profile.copyWith(name: name, pushEnabled: pushEnabled)),
      SessionSignedOut() => null,
      SessionUnavailable() => null,
    };
    if (next == null) return;

    state = AsyncValue.data(next);
  }

  Future<void> signOut() async {
    final generation = _tokens.beginOperation();
    try {
      await ref.read(authRepositoryProvider).logout();
    } on ApiException {
      // 서버 로그아웃이 실패해도 로컬 토큰은 반드시 지운다.
    }
    try {
      await _clearTokens(generation);
    } catch (_) {
      // 스토어 정리가 실패해도 사용자가 요청한 로그아웃 자체는 반드시
      // 반영한다 — 화면이 여전히 로그인 상태로 남아있으면 안 된다.
    } finally {
      _publish(generation, const SessionSignedOut());
    }
  }

  /// 커맨드(onAuthenticated/refreshProfile/signOut)가 결과를 상태로
  /// 내보내는 유일한 경로. [generation]이 낡았다면 **아무것도 하지 않는다** —
  /// 예전에는 이 자리에서 `_settle`이 돌려준 "현재 상태"를 다시 대입했는데,
  /// 아직 아무 상태도 발행되지 않았을 때는 그 값이 실제로는 존재한 적 없는
  /// SessionUnavailable이라, 진행 중인 최신 로그인 위에 재시도 화면을
  /// 덮어씌울 수 있었다.
  void _publish(int generation, SessionState result) {
    if (generation != _tokens.generation) return;
    state = AsyncValue.data(result);
  }

  /// [_resolve]가 build()에 돌려줄 값을 고른다. 커맨드와 달리 build()의
  /// 반환값은 Riverpod가 대신 상태에 대입하므로 "아무것도 하지 않는다"를
  /// 고를 수 없다 — 낡았다면 지금 상태를 그대로 되돌려 현상 유지시킨다.
  SessionState _settle(int generation, SessionState result) {
    if (generation != _tokens.generation) return _current();
    return result;
  }

  /// 세대가 어긋나 결과를 버릴 때 돌려줄, 지금 이 순간의 상태. 아직 어떤
  /// 상태도 발행된 적이 없다면(= 최초 판별이 끝나기도 전에 세대가 어긋난
  /// 경우) 스플래시가 재시도 UI를 띄우는 상태로 떨어진다 — 사용자가 버튼
  /// 하나로 다시 판별시킬 수 있으므로 갇히지 않는다.
  SessionState _current() {
    return state.value ?? const SessionUnavailable('세션 판별이 취소되었습니다.');
  }

  Future<void> _writeTokens(
    int generation, {
    required String accessToken,
    required String refreshToken,
  }) {
    return _tokens.save(
      generation,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> _clearTokens(int generation) => _tokens.clear(generation);
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);
