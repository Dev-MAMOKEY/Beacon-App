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
}

/// `GET /clubs/{clubId}/members`의 항목.
@JsonSerializable(createToJson: false)
class ClubMember {
  const ClubMember({
    required this.memberId,
    required this.name,
    required this.stdId,
    required this.role,
  });

  factory ClubMember.fromJson(Map<String, dynamic> json) => _$ClubMemberFromJson(json);

  final int memberId;
  final String name;

  /// 내가 누구인지 찾는 **유일한 키**다 — `GET /members/me`가 돌려주는
  /// `MemberProfileResponse`에는 `memberId`가 없어서 학번으로 잇는다.
  final String stdId;

  @JsonKey(fromJson: ClubRole.fromWire)
  final ClubRole role;
}

abstract interface class ClubMemberRepository {
  Future<List<ClubMember>> fetchMembers(int clubId);
}

class HttpClubMemberRepository implements ClubMemberRepository {
  const HttpClubMemberRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<ClubMember>> fetchMembers(int clubId) {
    return _client.get<List<ClubMember>>(
      '/clubs/$clubId/members',
      parse: (json) => (json! as List<dynamic>)
          .map((item) => ClubMember.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

final clubMemberRepositoryProvider = Provider<ClubMemberRepository>((ref) {
  return HttpClubMemberRepository(ref.watch(apiClientProvider));
});
