import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../design_system/design_system.dart';

/// The camera edge used by the invite screen.
///
/// Tests provide a scanner that calls [onCapture] without opening a camera.
abstract interface class InviteQrScanner {
  bool get isSupported;
  Future<bool> isAvailable();

  Widget build({required ValueChanged<String> onCapture});
}

/// The production camera implementation. It is only mounted after the person
/// chooses "Ler QR code".
final class MobileInviteQrScanner implements InviteQrScanner {
  const MobileInviteQrScanner();

  @override
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      final lenses = await MobileScannerPlatform.instance.getSupportedLenses(
        facing: CameraFacing.back,
      );
      return lenses.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Widget build({required ValueChanged<String> onCapture}) {
    return _MobileScannerPreview(onCapture: onCapture);
  }
}

final class _MobileScannerPreview extends StatefulWidget {
  const _MobileScannerPreview({required this.onCapture});

  final ValueChanged<String> onCapture;

  @override
  State<_MobileScannerPreview> createState() => _MobileScannerPreviewState();
}

final class _MobileScannerPreviewState extends State<_MobileScannerPreview> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _captured = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: TainaRadii.lgAll,
      child: MobileScanner(
        controller: _controller,
        onDetect: _handleCapture,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(TainaSpacing.space4),
            child: ErrorCard(
              title: 'Não conseguimos abrir a câmera.',
              body: 'Confira se este aparelho permite usar a câmera.',
            ),
          ),
        ),
      ),
    );
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_captured) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _captured = true;
      widget.onCapture(value);
      return;
    }
  }
}
