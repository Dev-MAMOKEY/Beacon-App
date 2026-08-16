import 'package:json_annotation/json_annotation.dart';

part 'auth_dto.g.dart';

@JsonSerializable(createToJson: false)
class TokenResponse {
  const TokenResponse({required this.accessToken, required this.refreshToken});

  factory TokenResponse.fromJson(Map<String, dynamic> json) =>
      _$TokenResponseFromJson(json);

  final String accessToken;
  final String refreshToken;
}

@JsonSerializable(createToJson: false)
class MemberProfile {
  const MemberProfile({
    required this.name,
    required this.stdId,
    required this.clubIds,
    required this.pushEnabled,
    this.title,
  });

  factory MemberProfile.fromJson(Map<String, dynamic> json) =>
      _$MemberProfileFromJson(json);

  final String name;
  final String stdId;

  @JsonKey(defaultValue: <int>[])
  final List<int> clubIds;

  @JsonKey(defaultValue: false)
  final bool pushEnabled;

  final String? title;

  /// 이 기기에서 방금 수정에 성공한 필드만 갈아끼운다. `PATCH /members/me`가
  /// 바꿀 수 있는 것 중 마이페이지(#13)가 실제로 건드리는 두 개만 받는다 —
  /// [stdId]·[clubIds]는 이 화면에서 바뀔 수 없고, [title]은 아직 어떤
  /// 화면도 수정하지 않는다. 필요해지는 화면이 생기면 그때 인자를 늘린다.
  MemberProfile copyWith({String? name, bool? pushEnabled}) => MemberProfile(
    name: name ?? this.name,
    stdId: stdId,
    clubIds: clubIds,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    title: title,
  );

  bool get hasClub => clubIds.isNotEmpty;

  /// MVP는 단일 동아리만 지원한다 (명세서 §동아리 및 초대코드).
  int get primaryClubId => clubIds.first;
}
