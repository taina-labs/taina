import 'dart:async';

import 'package:flutter/material.dart';
import 'package:okena_app/src/design_system/design_system.dart';
import 'package:okena_app/src/features/account/devices_model.dart';
import 'package:okena_app/src/session/session_gateway.dart';
import 'package:okena_core/okena_core.dart';
import 'package:provider/provider.dart';

/// The devices that can open this community.
final class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    required this.session,
    this.onBack,
    this.backLabel = 'Conta',
    super.key,
  });

  final SessionGateway session;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

final class _DevicesScreenState extends State<DevicesScreen> {
  late final DevicesModel _model;

  @override
  void initState() {
    super.initState();
    _model = DevicesModel(gateway: widget.session);
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DevicesModel>.value(
      value: _model,
      child: _DevicesView(onBack: widget.onBack, backLabel: widget.backLabel),
    );
  }
}

final class _DevicesView extends StatelessWidget {
  const _DevicesView({required this.onBack, required this.backLabel});

  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final DevicesModel model = context.watch<DevicesModel>();
    final List<DeviceToken>? devices = model.devices;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: model.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PageHeaderSliver(
                title: 'Dispositivos',
                backLabel: backLabel,
                onBack: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              if (model.actionError case final TainaError error)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: TainaToast(
                      kind: TainaToastKind.error,
                      text: error.message,
                    ),
                  ),
                ),
              if (devices == null && model.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(TainaSpacing.space4),
                    child: SkeletonView(
                      kind: TainaSkeletonKind.listRow,
                      count: 3,
                    ),
                  ),
                )
              else if (devices == null && model.error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(TainaSpacing.space4),
                    child: ErrorCard(
                      title: 'Não conseguimos carregar os aparelhos.',
                      body: model.error!.message,
                      retry: model.load,
                    ),
                  ),
                )
              else if (devices case final List<DeviceToken> values
                  when values.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyStateView(
                      icon: TainaIcon.dispositivos,
                      title: 'Nenhum aparelho',
                      body:
                          'Os aparelhos que entram na sua conta aparecem aqui.',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    TainaSpacing.space4,
                    TainaSpacing.space2,
                    TainaSpacing.space4,
                    TainaSpacing.space6,
                  ),
                  sliver: SliverList.builder(
                    itemCount: devices!.length,
                    itemBuilder: (BuildContext context, int index) {
                      final DeviceToken device = devices[index];
                      final bool isCurrent =
                          device.publicId == model.currentDevice?.publicId;
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: TainaSpacing.space2,
                        ),
                        child: isCurrent
                            ? _currentDevice(device)
                            : _otherDevice(
                                context,
                                model,
                                device,
                                canRevoke: model.currentDevice != null,
                              ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _currentDevice(DeviceToken device) {
    return TainaCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TainaListRow(
            kind: TainaListRowKind.civic,
            title: device.name,
            meta: DevicesModel.deviceLine(device),
            leadingBuilder: (_) =>
                const ServiceSquare(mark: TainaServiceMark.dispositivos),
            showDivider: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TainaSpacing.space4,
              TainaSpacing.space3,
              TainaSpacing.space4,
              TainaSpacing.space4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Este aparelho', style: TainaTypography.label),
                const SizedBox(height: TainaSpacing.space2),
                const Text(
                  'Identificação deste aparelho',
                  style: TainaTypography.caption,
                ),
                const SizedBox(height: TainaSpacing.space1),
                SelectableText(
                  device.publicId,
                  maxLines: 1,
                  style: TainaTypography.monoSm.copyWith(
                    color: TainaPalette.textMuted,
                  ),
                ),
                const SizedBox(height: TainaSpacing.space1),
                const Text(
                  'É assim que a comunidade distingue este aparelho dos outros.',
                  style: TainaTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _otherDevice(
    BuildContext context,
    DevicesModel model,
    DeviceToken device, {
    required bool canRevoke,
  }) {
    final bool revoked = device.revokedAt != null;
    final bool working = model.revokingDevice == device.publicId;
    return TainaListRow(
      kind: TainaListRowKind.civic,
      title: device.name,
      meta: DevicesModel.deviceLine(device),
      leadingBuilder: (_) =>
          const ServiceSquare(mark: TainaServiceMark.dispositivos),
      trailing: !revoked && canRevoke
          ? TainaListRowTrailing.action
          : TainaListRowTrailing.none,
      trailingLabel: 'Revogar',
      onTrailingPressed: revoked || working || !canRevoke
          ? null
          : () => unawaited(_revoke(context, model, device)),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    DevicesModel model,
    DeviceToken device,
  ) async {
    final bool? confirmed = await TainaDialog.destructive(
      context: context,
      title: 'Revogar o acesso deste aparelho?',
      message:
          '"${device.name}" perde o acesso à comunidade. Para voltar, é '
          'preciso entrar de novo nele.',
      confirmLabel: 'Revogar',
      useRootNavigator: false,
    );
    if (confirmed != true || !context.mounted) return;
    final TainaResult<void> result = await model.revokeDevice(device.publicId);
    if (result case Err(:final error)) {
      if (context.mounted) _showFailure(context, error);
    }
  }

  void _showFailure(BuildContext context, TainaError error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          content: TainaToast(kind: TainaToastKind.error, text: error.message),
        ),
      );
  }
}
