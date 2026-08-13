import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/network/error_code.dart';
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

// 자격-증명-죽음 판정은 core/network/error_code.dart의 authFailureCodes /
// isAuthFailureCode가 정본이다. AuthInterceptor도 같은 판정을 쓴다 — 두
// 곳이 각자 사본을 갖고 있다가 하나가 새 코드를 놓치는 사고를 막기 위해
// 이 파일에는 더 이상 별도 집합을 두지 않는다.

class SessionController extends AsyncNotifier<SessionState> {
  /// 진행 중인 판별(_resolve)이나 커맨드(onAuthenticated/refreshProfile/
  /// signOut)가 여러 개 겹칠 때, 가장 나중에 시작한 것만 상태와 스토리지에
  /// 반영되도록 하는 세대 번호. build()가 다시 호출되는 것(초기 진입,
  /// sessionExpiredProvider 증가, 재시도용 invalidate)도 여기 포함된다 —
  /// Riverpod는 build() 호출이 새로 시작되면 이전 build()의 *상태 반영*은
  /// 알아서 버리지만, 이미 시작된 부수효과(토큰 저장/삭제)까지 취소해주지는
  /// 않으므로 그 부분은 이 카운터로 직접 막는다.
  int _generation = 0;

  /// 토큰 저장소에 대한 모든 쓰기(save/clear)를 이 큐로 직렬화한다. 세대
  /// 검사만으로는 "쓰기 호출 자체는 막지 못하고 그 결과 반영만 막는" 반쪽
  /// 방어가 된다 — 커맨드/판별이 겹치면 늦게 시작한 쪽의 save()가 먼저
  /// 끝나고, 먼저 시작한 쪽의 save()가 나중에 끝나 저장소를 조용히
  /// 되돌릴 수 있다. 모든 쓰기를 한 큐로 순서대로 실행하면 "나중에 큐에
  /// 들어온 쓰기가 항상 마지막에 저장소에 닿는다"가 보장되고, 큐 차례가
  /// 됐을 때 세대를 다시 확인해 이미 낡은 요청이면 아예 쓰지 않는다.
  Future<void> _tokenWriteQueue = Future<void>.value();

  @override
  Future<SessionState> build() async {
    // 인터셉터가 재발급에 실패하면 이 값이 증가한다. 그때 다시 판별한다.
    ref.watch(sessionExpiredProvider);
    return _resolve();
  }

  Future<SessionState> _resolve() async {
    final generation = ++_generation;
    final store = ref.read(tokenStoreProvider);

    final String? refreshToken;
    try {
      refreshToken = await store.readRefreshToken();
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
      if (generation != _generation) return _current();

      await _writeTokens(
        generation,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );

      final profile = await repository.fetchMe();
      final resolved = profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
      return _settle(generation, resolved);
    } on ApiException catch (error) {
      if (isAuthFailureCode(error.code)) {
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
    final generation = ++_generation;
    state = const AsyncValue.loading();

    SessionState result;
    try {
      await _writeTokens(
        generation,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      if (generation != _generation) {
        state = AsyncValue.data(_current());
        return;
      }

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
      if (isAuthFailureCode(error.code)) {
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

    state = AsyncValue.data(_settle(generation, result));
  }

  /// 초대코드 가입 성공 직후 호출한다.
  Future<void> refreshProfile() async {
    final generation = ++_generation;

    SessionState result;
    try {
      final profile = await ref.read(authRepositoryProvider).fetchMe();
      result = profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
    } on ApiException catch (error) {
      if (isAuthFailureCode(error.code)) {
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

    state = AsyncValue.data(_settle(generation, result));
  }

  Future<void> signOut() async {
    final generation = ++_generation;
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
      state = AsyncValue.data(_settle(generation, const SessionSignedOut()));
    }
  }

  /// [generation]이 이 커맨드/판별이 시작된 이후로 바뀌지 않았을 때만
  /// [result]를 반영한다. 바뀌었다면 그 사이 다른 커맨드가 이미 최신 상태를
  /// 발행했다는 뜻이므로 [result]는 버리고 현재 상태를 그대로 돌려준다.
  SessionState _settle(int generation, SessionState result) {
    if (generation != _generation) return _current();
    return result;
  }

  /// 세대가 어긋나 결과를 버릴 때 돌려줄, 지금 이 순간의 상태. 최초 판별이
  /// 시작되기도 전에 세대가 어긋나는 경우처럼 아직 어떤 상태도 없다면
  /// 안전한 기본값으로 떨어진다.
  SessionState _current() {
    return state.value ?? const SessionUnavailable('세션 판별이 취소되었습니다.');
  }

  Future<void> _writeTokens(
    int generation, {
    required String accessToken,
    required String refreshToken,
  }) {
    return _enqueueTokenWrite(
      generation,
      () => ref.read(tokenStoreProvider).save(
            accessToken: accessToken,
            refreshToken: refreshToken,
          ),
    );
  }

  Future<void> _clearTokens(int generation) {
    return _enqueueTokenWrite(generation, () => ref.read(tokenStoreProvider).clear());
  }

  /// [write]를 `_tokenWriteQueue`에 이어붙여 실행한다. 이 요청보다 먼저
  /// 큐에 들어온 쓰기가 전부 끝난 뒤 자기 차례가 됐을 때 세대를 다시
  /// 확인하고, 그 사이 더 최신 커맨드/판별이 시작됐다면(세대가 바뀌었다면)
  /// 아예 쓰지 않고 건너뛴다. 개별 쓰기가 실패해도 큐 자체는 막히지 않게
  /// 다음 쓰기로 넘어갈 수 있는 채널을 항상 유지한다.
  Future<void> _enqueueTokenWrite(int generation, Future<void> Function() write) {
    final scheduled = _tokenWriteQueue.then((_) {
      if (generation != _generation) return Future<void>.value();
      return write();
    });
    _tokenWriteQueue = scheduled.then((_) {}, onError: (_) {});
    return scheduled;
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);
