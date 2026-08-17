import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/dio_provider.dart';

part 'club_member_repository.g.dart';

/// 동아리 안에서의 역할. 관리자 탭 노출과 `/admin` 진입 허용이 이 값 하나에
/// 달려 있다.
enum ClubRole {
  admin,
  member;

  /// 모르는 값을 `member`로 접지 **않는다.** 조용히 접으면 서버가 새 역할을
  /// 추가했을 때 관리자가 자기 화면에 못 들어가고, 원인은 앱 어디에도
  /// 남지 않는다.
  static ClubRole fromWire(String wire) => switch (wire) {
    'ADMIN' => ClubRole.admin,
    'MEMBER' => ClubRole.member,
    _ => throw FormatException('알 수 없는 역할: $wire'),
  };

  /// 서버로 되돌려 보낼 문자열. Dart enum 이름(`admin`)을 그대로 보내면
  /// 서버가 알아듣지 못한다.
  String get wire => switch (this) {
    ClubRole.admin => 'ADMIN',
    ClubRole.member => 'MEMBER',
  };
}

/// `GET /clubs/{clubId}/members`의 항목.
@JsonSerializable(createToJson: false)
class ClubMember {
  const ClubMember({
    required this.memberId,
    required this.name,
    required this.stdId,
    required this.role,
    this.part,
    this.rate,
    this.attendanceCount,
  });

  factory ClubMember.fromJson(Map<String, dynamic> json) => _$ClubMemberFromJson(json);

  final int memberId;
  final String name;

  /// 내가 누구인지 찾는 **유일한 키**다 — `GET /members/me`가 돌려주는
  /// `MemberProfileResponse`에는 `memberId`가 없어서 학번으로 잇는다.
  final String stdId;

  @JsonKey(fromJson: ClubRole.fromWire)
  final ClubRole role;

  /// 동아리 안의 파트(프론트엔드·기획·디자인…). 웹 멤버 표(`356:1627`)의
  /// "역할" 열이 이 값이다 — [role](ADMIN/MEMBER)과 **다른 필드**다.
  ///
  /// 자유 문자열이라 서버가 정한 목록이 없다.
  final String? part;

  /// 출석률(0~100). 웹의 "출석률" 열.
  final num? rate;

  /// 출석 횟수. 웹의 "출석 횟수" 열.
  final int? attendanceCount;
}

abstract interface class ClubMemberRepository {
  /// [search]가 있으면 서버가 걸러 준다. 비어 있으면 파라미터 자체를 빼서
  /// 전체를 받는다 — 빈 문자열을 보내면 서버 구현에 따라 "빈 이름과 일치"로
  /// 해석돼 아무도 안 나올 수 있다.
  Future<List<ClubMember>> fetchMembers(int clubId, {String? search});

  /// 역할(ADMIN/MEMBER)을 바꾼다.
  ///
  /// [requesterId]는 서버가 "누가 바꾸려 하는가"를 확인하는 값이다.
  /// `GET /members/me`에는 `memberId`가 없어서, 멤버 목록에서 **학번으로**
  /// 자신을 찾아 넘겨야 한다.
  Future<void> updateRole({
    required int clubId,
    required int requesterId,
    required int targetMemberId,
    required ClubRole newRole,
  });

  /// 동아리에서 제외한다.
  Future<void> removeMember({required int clubId, required int memberId});
}

class HttpClubMemberRepository implements ClubMemberRepository {
  const HttpClubMemberRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<ClubMember>> fetchMembers(int clubId, {String? search}) {
    final trimmed = search?.trim();
    return _client.get<List<ClubMember>>(
      '/clubs/$clubId/members',
      query: {
        if (trimmed != null && trimmed.isNotEmpty) 'search': trimmed,
      },
      parse: (json) => (json! as List<dynamic>)
          .map((item) => ClubMember.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<void> updateRole({
    required int clubId,
    required int requesterId,
    required int targetMemberId,
    required ClubRole newRole,
  }) {
    return _client.patch<void>(
      '/clubs/$clubId/members/$targetMemberId/role',
      // 경로에 이미 있는 값을 본문에도 요구한다(`RoleUpdateRequest`) —
      // 서버 스키마가 그렇다.
      body: {
        'clubId': clubId,
        'requesterId': requesterId,
        'targetMemberId': targetMemberId,
        'newRole': newRole.wire,
      },
      parse: (_) {},
    );
  }

  @override
  Future<void> removeMember({required int clubId, required int memberId}) {
    return _client.delete<void>('/clubs/$clubId/members/$memberId', parse: (_) {});
  }
}

final clubMemberRepositoryProvider = Provider<ClubMemberRepository>((ref) {
  return HttpClubMemberRepository(ref.watch(apiClientProvider));
});
