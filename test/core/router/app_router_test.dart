import 'package:beacon_app/core/router/app_router.dart';
import 'package:beacon_app/features/auth/data/auth_dto.dart';
import 'package:beacon_app/features/auth/presentation/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _profileWithClub = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [7],
  pushEnabled: true,
);

const _profileNoClub = MemberProfile(
  name: '김민준',
  stdId: '20250101',
  clubIds: [],
  pushEnabled: true,
);

void main() {
  final launchedAt = DateTime(2026, 1, 1);
  final beforeMinDuration = launchedAt.add(const Duration(milliseconds: 100));
  final afterMinDuration = launchedAt.add(const Duration(milliseconds: 1600));

  String? redirect({
    required AsyncValue<SessionState> session,
    required String matchedLocation,
    DateTime? now,
    // 프로덕션 기본값(showAdminTabProvider)과 맞춘다 — 이 값이 결과에
    // 영향을 주는 시나리오만 명시적으로 override한다.
    bool showAdmin = false,
  }) {
    return computeRedirect(
      session: session,
      matchedLocation: matchedLocation,
      launchedAt: launchedAt,
      now: now ?? afterMinDuration,
      showAdmin: showAdmin,
    );
  }

  group('로딩/에러 상태', () {
    test('로딩 중이면 다른 화면에 있어도 스플래시로 보낸다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.loading(),
        matchedLocation: AppRoutes.home,
      );
      expect(result, AppRoutes.splash);
    });

    test('로딩 중이고 이미 스플래시면 리다이렉트하지 않는다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.loading(),
        matchedLocation: AppRoutes.splash,
      );
      expect(result, isNull);
    });

    test('AsyncError는 이전 값이 남아있어도(hasValue) 스플래시에 머무른다', () {
      const previous = AsyncValue<SessionState>.data(SessionReady(_profileWithClub));
      final errored = AsyncValue<SessionState>.error(Exception('boom'), StackTrace.empty)
          .copyWithPrevious(previous);

      // 이 시나리오가 실제로 hasValue == true인 AsyncError인지 먼저 확인한다
      // — 그렇지 않다면 아래 검증이 의미가 없다.
      expect(errored.hasValue, isTrue);
      expect(errored.hasError, isTrue);

      final result = redirect(session: errored, matchedLocation: AppRoutes.home);
      expect(result, AppRoutes.splash);
    });

    test('AsyncError면 requireValue로 낡은 SessionReady를 읽어 /home으로 보내지 않는다', () {
      const previous = AsyncValue<SessionState>.data(SessionReady(_profileWithClub));
      final errored = AsyncValue<SessionState>.error(Exception('boom'), StackTrace.empty)
          .copyWithPrevious(previous);

      final result = redirect(session: errored, matchedLocation: AppRoutes.splash);
      expect(result, isNull); // 스플래시에 머무름 — /home으로 새지 않는다.
    });
  });

  group('세션 상태별 목적지 (최소 노출 시간 경과 후)', () {
    test('SignedOut -> /login', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionSignedOut()),
        matchedLocation: AppRoutes.splash,
      );
      expect(result, AppRoutes.login);
    });

    test('NeedsClub -> /invite', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionNeedsClub(_profileNoClub)),
        matchedLocation: AppRoutes.splash,
      );
      expect(result, AppRoutes.invite);
    });

    test('Ready -> /home', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.splash,
      );
      expect(result, AppRoutes.home);
    });

    test('이미 목적지 화면이면 리다이렉트하지 않는다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.home,
      );
      expect(result, isNull);
    });

    test('SignedOut인데 회원가입 화면이면 막지 않는다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionSignedOut()),
        matchedLocation: AppRoutes.signup,
      );
      expect(result, isNull);
    });

    test('SessionUnavailable은 스플래시에 머무른다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionUnavailable('오류')),
        matchedLocation: AppRoutes.splash,
      );
      expect(result, isNull);
    });

    test('SessionUnavailable인데 다른 화면에 있으면 스플래시로 되돌린다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionUnavailable('오류')),
        matchedLocation: AppRoutes.home,
      );
      expect(result, AppRoutes.splash);
    });
  });

  group('최소 스플래시 노출 시간 (1.5초)', () {
    test('1.5초 전에는 판별이 끝났어도(Ready) 스플래시에 머무른다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.home,
        now: beforeMinDuration,
      );
      expect(result, AppRoutes.splash);
    });

    test('1.5초가 지나면 Ready가 /home으로 이동한다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.splash,
        now: afterMinDuration,
      );
      expect(result, AppRoutes.home);
    });

    test('SessionUnavailable은 1.5초를 기다리지 않고 즉시 알린다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionUnavailable('오류')),
        matchedLocation: AppRoutes.splash,
        now: beforeMinDuration,
      );
      expect(result, isNull); // 이미 스플래시 — 재시도 UI가 바로 보인다.
    });
  });

  // 하단 탭이 생기면서 SessionReady는 더 이상 /home 하나만 허용하지 않는다.
  // 이 group은 그 허용 위치 집합을 고정한다 — 예전의 단일 타겟 로직으로
  // 되돌아가면(또는 집합 검사가 다른 세션 상태에도 새어 나가면) 실패해야
  // 한다.
  group('허용 위치 집합 (하단 탭)', () {
    test('Ready가 /records에 있으면 리다이렉트하지 않는다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.records,
      );
      expect(result, isNull);
    });

    test('Ready가 /profile에 있으면 리다이렉트하지 않는다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.profile,
      );
      expect(result, isNull);
    });

    test('Ready가 허용 집합 밖(/nonsense)이면 /home으로 보낸다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: '/nonsense',
      );
      expect(result, AppRoutes.home);
    });

    test('SignedOut이 /records에 있으면 /login으로 보낸다 — 허용 집합 확장은 Ready에만 적용된다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionSignedOut()),
        matchedLocation: AppRoutes.records,
      );
      expect(result, AppRoutes.login);
    });
  });

  // 관리자 가드가 GoRouter의 redirect: 클로저가 아니라 computeRedirect
  // 자체 안에 있는지 고정한다 — 밖에 있으면 이 group의 두 테스트는 가드가
  // 통째로 사라져도 여전히 초록색이다(가드를 별도로 두고 지워봤을 때
  // 실제로 그랬다 — 아래 각 테스트에 판별 결과를 남겼다).
  group('관리자 라우트 가드', () {
    test('showAdmin이 false면 /admin을 /home으로 되돌린다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.admin,
      );
      expect(result, AppRoutes.home);
    });

    test('showAdmin이 true면 /admin에 머무른다', () {
      final result = redirect(
        session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
        matchedLocation: AppRoutes.admin,
        showAdmin: true,
      );
      expect(result, isNull);
    });
  });
}
