import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// The pt-BR prompts the files and trash screens share. Small, stateless
/// helpers over Material dialogs so every confirmation reads the same.

/// Asks for a name, returning the trimmed value or null when cancelled.
Future<String?> showNamePrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? help,
  String confirmLabel = 'Salvar',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NamePromptDialog(
      title: title,
      label: label,
      initial: initial,
      help: help,
      confirmLabel: confirmLabel,
    ),
  );
}

final class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.help,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String initial;
  final String? help;
  final String confirmLabel;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

final class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirm(),
            style: TainaTypography.body.copyWith(
              color: TainaPalette.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: widget.label,
              hintStyle: TainaTypography.body.copyWith(
                color: TainaPalette.textFaint,
              ),
            ),
          ),
          if (widget.help != null) ...[
            const SizedBox(height: TainaSpacing.space3),
            TainaText(
              widget.help!,
              style: TainaTypography.caption,
              color: TainaPalette.textMuted,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// One confirmation with the title and the sentence the web asks for.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: TainaPalette.feedbackError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// The one failure alert the screens show: the server's own pt-BR sentence
/// when it has one, a local sentence otherwise.
Future<void> showFailure(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Não deu certo'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
}
