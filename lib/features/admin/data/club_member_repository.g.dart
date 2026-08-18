// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'club_member_repository.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClubMember _$ClubMemberFromJson(Map<String, dynamic> json) => ClubMember(
  memberId: (json['memberId'] as num).toInt(),
  name: json['name'] as String,
  stdId: json['stdId'] as String,
  role: ClubRole.fromWire(json['role'] as String),
  part: json['part'] as String?,
  rate: json['rate'] as num?,
  attendanceCount: (json['attendanceCount'] as num?)?.toInt(),
);
