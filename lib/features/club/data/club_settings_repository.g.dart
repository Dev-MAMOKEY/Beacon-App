// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'club_settings_repository.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClubDetail _$ClubDetailFromJson(Map<String, dynamic> json) => ClubDetail(
  id: (json['id'] as num).toInt(),
  clubName: json['clubName'] as String,
  clubDescription: json['clubDescription'] as String?,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
);
