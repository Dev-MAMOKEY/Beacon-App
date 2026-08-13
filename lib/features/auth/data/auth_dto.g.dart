// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TokenResponse _$TokenResponseFromJson(Map<String, dynamic> json) =>
    TokenResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );

MemberProfile _$MemberProfileFromJson(Map<String, dynamic> json) =>
    MemberProfile(
      name: json['name'] as String,
      stdId: json['stdId'] as String,
      clubIds:
          (json['clubIds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      pushEnabled: json['pushEnabled'] as bool? ?? false,
      title: json['title'] as String?,
    );
