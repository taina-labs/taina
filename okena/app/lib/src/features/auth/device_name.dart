import 'package:flutter/foundation.dart';

/// Builds a useful device label without reading platform state or doing IO.
String authDeviceName({required TargetPlatform platform, String? username}) {
  final platformName = switch (platform) {
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.android => 'Android',
    _ => 'Aparelho',
  };
  final person = username?.trim().toLowerCase();
  if (person == null || person.isEmpty) return platformName;
  return '$platformName de $person';
}
