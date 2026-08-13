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

/// refresh 응답 코드 중 "자격 증명 자체가 죽었다"는 뜻인 것만 SignedOut으로
/// 취급한다. 그 외(네트워크 단절, 5xx, 파싱 실패 등)는 토큰을 지울 근거가
/// 없다 — 다시 시도하면 될 수도 있는 일시적 실패다.
const Set<ErrorCode> _authFailureCodes = {
  ErrorCode.tokenExpired,
  ErrorCode.tokenInvalid,
  ErrorCode.tokenMissing,
  ErrorCode.refreshTokenRevoked,
  ErrorCode.invalidCredentials,
};

bool _isAuthFailure(ErrorCode code) => _authFailureCodes.contains(code);

class SessionController extends AsyncNotifier<SessionState> {
  /// 진행 중인 판별(_resolve)이나 커맨드(onAuthenticated/refreshProfile/
  /// signOut)가 여러 개 겹칠 때, 가장 나중에 시작한 것만 상태와 스토리지에
  /// 반영되도록 하는 세대 번호. build()가 다시 호출되는 것(초기 진입,
  /// sessionExpiredProvider 증가, 재시도용 invalidate)도 여기 포함된다 —
  /// Riverpod는 build() 호출이 새로 시작되면 이전 build()의 *상태 반영*은
  /// 알아서 버리지만, 이미 시작된 부수효과(토큰 저장/삭제)까지 취소해주지는
  /// 않으므로 그 부분은 이 카운터로 직접 막는다.
  int _generation = 0;

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
      // 받은 토큰은 낡은 것일 수 있다 — 저장하지 않고 그대로 포기한다.
      if (generation != _generation) return _current();

      await store.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );

      final profile = await repository.fetchMe();
      final resolved = profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
      return _settle(generation, resolved);
    } on ApiException catch (error) {
      if (_isAuthFailure(error.code)) {
        if (generation == _generation) {
          try {
            await store.clear();
          } catch (_) {
            // 스토어 정리 실패는 무시한다 — 어차피 SignedOut으로 보고한다.
          }
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
      await ref.read(tokenStoreProvider).save(
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
      result = SessionUnavailable(error.message);
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
      result = SessionUnavailable(error.message);
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
      await ref.read(tokenStoreProvider).clear();
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
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);
