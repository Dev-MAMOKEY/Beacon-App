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

    test('Ready가 허용 집합 밖이면 /home으로 보낸다', () {
      // 서로 다른 임의 경로 두 개를 확인한다 — 하나만 확인하면
      // "이 리터럴 하나만 걸러내고 나머지는 다 통과시키는" 구현도
      // 우연히 통과해 버린다.
      for (final bogus in ['/nonsense', '/totally-different-bogus-path']) {
        final result = redirect(
          session: const AsyncValue<SessionState>.data(SessionReady(_profileWithClub)),
          matchedLocation: bogus,
        );
        expect(result, AppRoutes.home, reason: '$bogus는 허용 집합 밖이라 /home으로 가야 한다');
      }
    });

    test('SignedOut은 허용 집합의 어떤 위치에 있어도 /login으로 보낸다 — 허용 집합 확장은 Ready에만 적용된다', () {
      // /records 하나만 확인하면 "SignedOut일 때 /records만 특별히
      // 막고 나머지(/home, /admin, /profile)는 통과시키는" 구현도 그
      // 하나에 대해서는 우연히 맞아떨어져 통과해 버린다 — 실제로 그런
      // 잘못된 구현으로 이 테스트 하나만 돌렸더니 통과했다(아래 참고).
      // 허용 집합 전체를 순회해야 그 틈을 잡는다.
      for (final location in readyAllowedLocations) {
        final result = redirect(
          session: const AsyncValue<SessionState>.data(SessionSignedOut()),
          matchedLocation: location,
        );
        expect(result, AppRoutes.login, reason: 'SignedOut은 $location에서도 /login으로 가야 한다');
      }
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

    // isAdminRoute 자체를 직접 테스트한다 — computeRedirect를 블랙박스로만
    // 찔러 보면, readyAllowedLocations에 /admin의 자식이 아직 하나도
    // 없어서 접두사 규칙과 정확히-일치 규칙이 오늘 시점엔 결과가 똑같다
    // (둘 다 "집합에 없으니 /home"). Phase 3가 /admin/settings 같은
    // 자식을 허용 집합에 추가하는 순간에만 차이가 드러나는데, 그건 아직
    // 존재하지 않는 라우트라 지어낼 수 없다 — 그래서 이 함수 자체를
    // 직접 고정해 둔다.
    test('/admin 뿐 아니라 그 하위 경로도 관리자 경로로 취급한다', () {
      expect(isAdminRoute('/admin/anything'), isTrue);
      expect(isAdminRoute(AppRoutes.admin), isTrue);
      expect(isAdminRoute(AppRoutes.records), isFalse);
    });
  });
}
