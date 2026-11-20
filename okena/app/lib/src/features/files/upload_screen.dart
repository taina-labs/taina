import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:okena_core/okena_core.dart';

import '../../design_system/design_system.dart';
import '../../session/upload_center.dart';

/// The one-file upload route. The session-owned center outlives this screen.
final class EnviarScreen extends StatefulWidget {
  const EnviarScreen({
    required this.center,
    required this.request,
    this.backLabel,
    this.onBack,
    this.onViewSpace,
    this.onCompleted,
    super.key,
  });

  final UploadCenter center;
  final UploadRequest request;
  final String? backLabel;
  final VoidCallback? onBack;
  final VoidCallback? onViewSpace;
  final VoidCallback? onCompleted;

  @override
  State<EnviarScreen> createState() => _EnviarScreenState();
}

final class _EnviarScreenState extends State<EnviarScreen> {
  bool _started = false;
  bool _completionNotified = false;

  @override
  void initState() {
    super.initState();
    widget.center.addListener(_uploadChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
  }

  @override
  void didUpdateWidget(EnviarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center != widget.center) {
      oldWidget.center.removeListener(_uploadChanged);
      widget.center.addListener(_uploadChanged);
    }
    if (oldWidget.request != widget.request) {
      _started = false;
      _completionNotified = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
    }
  }

  @override
  void dispose() {
    widget.center.removeListener(_uploadChanged);
    super.dispose();
  }

  void _startIfNeeded() {
    if (!mounted || _started) return;
    _started = true;
    final state = widget.center.state;
    if (state case UploadUploading(:final request)
        when request == widget.request) {
      return;
    }
    unawaited(widget.center.start(widget.request));
  }

  void _uploadChanged() {
    if (!mounted) return;
    final state = widget.center.state;
    if (state is UploadSucceeded && !_completionNotified) {
      _completionNotified = true;
      widget.onCompleted?.call();
    }
    setState(() {});
  }

  Future<void> _retry() async {
    await widget.center.retry();
  }

  void _back() {
    final callback = widget.onBack;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.center.state;
    final backLabel = widget.backLabel?.trim().isNotEmpty == true
        ? widget.backLabel!.trim()
        : 'Documentos';
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          PageHeaderSliver(
            title: 'Enviar',
            backLabel: backLabel,
            onBack: _back,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(TainaSpacing.space4),
            sliver: SliverToBoxAdapter(child: _content(state)),
          ),
        ],
      ),
    );
  }

  Widget _content(UploadState state) {
    if (state is UploadUploading) {
      return Semantics(
        container: true,
        label: state.progressTitle,
        child: UploadRow(
          fileName: state.request.name,
          status: UploadRowStatus.uploading,
          progress: state.progressFraction,
          detail: state.progressDetail,
          help: state.progressHelp,
        ),
      );
    }
    if (state is UploadFailed) {
      final quota =
          state.error is ApiError && (state.error as ApiError).isQuotaExceeded;
      return UploadRow(
        fileName: state.request.name,
        status: quota
            ? UploadRowStatus.quotaExceeded
            : UploadRowStatus.networkError,
        detail: quota ? null : state.error.message,
        onRetry: quota ? null : () => unawaited(_retry()),
        onViewSpace: widget.onViewSpace,
      );
    }
    if (state is UploadSucceeded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TainaToast(
            kind: TainaToastKind.info,
            text: 'Arquivo guardado na sua casa.',
          ),
          const SizedBox(height: TainaSpacing.space4),
          TainaButton(
            title: 'Voltar para Documentos',
            action: _back,
            kind: TainaButtonKind.secondary,
          ),
        ],
      );
    }
    return const EmptyStateView(
      icon: TainaIcon.upload,
      title: 'Preparando o envio',
      body: 'O arquivo será guardado na sua casa.',
    );
  }
}
