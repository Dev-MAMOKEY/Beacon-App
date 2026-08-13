import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_provider.dart';
import '../data/auth_dto.dart';
import '../data/auth_repository.dart';

sealed class SessionState {
  const SessionState();
}

/// 아직 판별 전. 스플래시가 이 상태를 보여준다.
class SessionUnknown extends SessionState {
  const SessionUnknown();
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

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    // 인터셉터가 재발급에 실패하면 이 값이 증가한다. 그때 다시 판별한다.
    ref.watch(sessionExpiredProvider);
    return _resolve();
  }

  Future<SessionState> _resolve() async {
    final store = ref.read(tokenStoreProvider);
    final refreshToken = await store.readRefreshToken();
    if (refreshToken == null) return const SessionSignedOut();

    final repository = ref.read(authRepositoryProvider);
    try {
      final tokens = await repository.refresh(refreshToken);
      await store.save(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      final profile = await repository.fetchMe();
      return profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
    } on ApiException {
      await store.clear();
      return const SessionSignedOut();
    }
  }

  /// 로그인/회원가입 성공 직후 호출한다.
  Future<void> onAuthenticated(TokenResponse tokens) async {
    state = const AsyncValue.loading();
    await ref.read(tokenStoreProvider).save(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        );
    state = await AsyncValue.guard(() async {
      final profile = await ref.read(authRepositoryProvider).fetchMe();
      return profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
    });
  }

  /// 초대코드 가입 성공 직후 호출한다.
  Future<void> refreshProfile() async {
    state = await AsyncValue.guard(() async {
      final profile = await ref.read(authRepositoryProvider).fetchMe();
      return profile.hasClub ? SessionReady(profile) : SessionNeedsClub(profile);
    });
  }

  Future<void> signOut() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } on ApiException {
      // 서버 로그아웃이 실패해도 로컬 토큰은 반드시 지운다.
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncValue.data(SessionSignedOut());
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);
