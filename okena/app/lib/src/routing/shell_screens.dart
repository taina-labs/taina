import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

typedef AppRouteBuilder = Widget Function(
  BuildContext context,
  GoRouterState state,
);

/// Builders composed by the app integration. Route definitions stay in
/// routing, while feature implementations can be replaced independently.
final class ShellScreens {
  const ShellScreens({
    this.home,
    this.documents,
    this.trash,
    this.folder,
    this.file,
    this.upload,
    this.gallery,
    this.galleryViewer,
    this.mural,
    this.health,
    this.members,
    this.inviteMember,
    this.storage,
    this.account,
    this.requests,
    this.privacy,
    this.devices,
    this.cameraRoll,
    this.invitePaste,
  });

  final AppRouteBuilder? home;
  final AppRouteBuilder? documents;
  final AppRouteBuilder? trash;
  final AppRouteBuilder? folder;
  final AppRouteBuilder? file;
  final AppRouteBuilder? upload;
  final AppRouteBuilder? gallery;
  final AppRouteBuilder? galleryViewer;
  final AppRouteBuilder? mural;
  final AppRouteBuilder? health;
  final AppRouteBuilder? members;
  final AppRouteBuilder? inviteMember;
  final AppRouteBuilder? storage;
  final AppRouteBuilder? account;
  final AppRouteBuilder? requests;
  final AppRouteBuilder? privacy;
  final AppRouteBuilder? devices;
  final AppRouteBuilder? cameraRoll;
  final AppRouteBuilder? invitePaste;
}
