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

  bool get hasClub => clubIds.isNotEmpty;

  /// MVP는 단일 동아리만 지원한다 (명세서 §동아리 및 초대코드).
  int get primaryClubId => clubIds.first;
}
