import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

import '../../design_system/design_system.dart';
import '../../session/session_gateway.dart';
import 'dialogs.dart';
import 'move_view_model.dart';

/// The move modal, one for files and folders alike: the root and every
/// folder, one tap to move. The sheet offers only the destinations the
/// client can vouch for: never the source itself, and for a folder source
/// none of its descendants, where the move would close a cycle.
///
/// What the record cannot say is ownership: the web filters to the person's
/// own folders, but the record the app reads carries no owner, so those still
/// show and the box has the last word.
final class MoveSheet extends StatelessWidget {
  const MoveSheet({
    required this.session,
    required this.sourceRkey,
    required this.name,
    required this.onPick,
    this.isFolder = false,
    this.model,
    super.key,
  });

  final SessionGateway session;
  final String sourceRkey;
  final String name;
  final bool isFolder;

  /// Moves the source under the chosen folder, null for the root. The sheet
  /// closes on success and shows the failure in place.
  final Future<TainaResult<void>> Function(Folder? folder) onPick;

  /// An already built model, for tests and previews.
  final MoveViewModel? model;

  @override
  Widget build(BuildContext context) {
    final body = _MoveSheetBody(name: name, onPick: onPick);
    final injected = model;
    if (injected != null) {
      return ChangeNotifierProvider<MoveViewModel>.value(
        value: injected,
        child: body,
      );
    }
    return ChangeNotifierProvider<MoveViewModel>(
      create: (context) {
        final created = MoveViewModel(
          session: session,
          sourceRkey: sourceRkey,
          isFolder: isFolder,
        );
        unawaited(created.load());
        return created;
      },
      child: body,
    );
  }
}

/// Opens [MoveSheet] as a modal bottom sheet.
Future<void> showMoveSheet(
  BuildContext context, {
  required SessionGateway session,
  required String sourceRkey,
  required String name,
  required Future<TainaResult<void>> Function(Folder? folder) onPick,
  bool isFolder = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => MoveSheet(
      session: session,
      sourceRkey: sourceRkey,
      name: name,
      isFolder: isFolder,
      onPick: onPick,
    ),
  );
}

final class _MoveSheetBody extends StatefulWidget {
  const _MoveSheetBody({required this.name, required this.onPick});

  final String name;
  final Future<TainaResult<void>> Function(Folder? folder) onPick;

  @override
  State<_MoveSheetBody> createState() => _MoveSheetBodyState();
}

final class _MoveSheetBodyState extends State<_MoveSheetBody> {
  bool _moving = false;

  Future<void> _pick(Folder? folder) async {
    if (_moving) return;
    setState(() => _moving = true);
    final result = await widget.onPick(folder);
    if (!mounted) return;
    setState(() => _moving = false);
    if (result.isSuccess) {
      Navigator.of(context).pop();
      return;
    }
    final error = result.error;
    if (error != null) await showFailure(context, error.message);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<MoveViewModel>();
    final height = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TainaSpacing.space4,
                TainaSpacing.space3,
                TainaSpacing.space2,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TainaText(
                      'Mover para...',
                      style: TainaTypography.h3,
                      color: TainaPalette.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: _moving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
            Expanded(child: _content(context, model)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, MoveViewModel model) {
    if (model.loading) return const TainaLoadingList();
    final error = model.error;
    if (error != null) {
      return TainaErrorState(error: error, onRetry: model.load);
    }
    final destinations = model.destinations;
    return ListView(
      padding: const EdgeInsets.all(TainaSpacing.space4),
      children: [
        TainaText(
          widget.name,
          style: TainaTypography.bodySm,
          color: TainaPalette.textMuted,
        ),
        const SizedBox(height: TainaSpacing.space4),
        _DestinationRow(
          icon: Icons.home_outlined,
          label: 'Início (raiz)',
          disabled: _moving,
          onTap: () => _pick(null),
        ),
        const SizedBox(height: TainaSpacing.space2),
        for (final folder in destinations) ...[
          _DestinationRow(
            icon: Icons.folder_rounded,
            label: folder.name,
            disabled: _moving,
            onTap: () => _pick(folder),
          ),
          const SizedBox(height: TainaSpacing.space2),
        ],
      ],
    );
  }
}

final class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TainaRowCard(
      onTap: disabled ? null : onTap,
      child: Row(
        children: [
          Icon(icon, size: TainaFontSizes.xl, color: TainaPalette.serviceYbira),
          const SizedBox(width: TainaSpacing.space3),
          Expanded(
            child: TainaText(
              label,
              style: TainaTypography.label,
              color: TainaPalette.textPrimary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
