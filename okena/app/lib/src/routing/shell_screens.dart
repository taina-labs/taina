import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

typedef AppRouteBuilder = Widget Function(
  BuildContext context,
  GoRouterState state,
);

/// Builders composed by the app integration. Route definitions stay in
/// routing, while feature implementations can be replaced independently.
/// Every registered route has a required builder; camera roll is present only
/// when its mirror runtime is composed.
final class ShellScreens {
  const ShellScreens({
    required this.home,
    required this.documents,
    required this.trash,
    required this.folder,
    required this.file,
    required this.upload,
    required this.gallery,
    required this.galleryViewer,
    required this.mural,
    required this.health,
    required this.members,
    required this.inviteMember,
    required this.storage,
    required this.account,
    required this.requests,
    required this.privacy,
    required this.devices,
    this.cameraRoll,
    required this.invitePaste,
  });

  final AppRouteBuilder home;
  final AppRouteBuilder documents;
  final AppRouteBuilder trash;
  final AppRouteBuilder folder;
  final AppRouteBuilder file;
  final AppRouteBuilder upload;
  final AppRouteBuilder gallery;
  final AppRouteBuilder galleryViewer;
  final AppRouteBuilder mural;
  final AppRouteBuilder health;
  final AppRouteBuilder members;
  final AppRouteBuilder inviteMember;
  final AppRouteBuilder storage;
  final AppRouteBuilder account;
  final AppRouteBuilder requests;
  final AppRouteBuilder privacy;
  final AppRouteBuilder devices;
  final AppRouteBuilder? cameraRoll;
  final AppRouteBuilder invitePaste;
}
