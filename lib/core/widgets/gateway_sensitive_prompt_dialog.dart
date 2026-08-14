import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../models/gateway_sensitive_prompt.dart';

typedef SensitivePromptResponder = Future<void> Function(String value);

enum GatewaySensitivePromptDialogResult { responded, expired }

class GatewaySensitivePromptDialog extends StatefulWidget {
  final GatewaySensitivePromptRequest request;
  final SensitivePromptResponder onRespond;

  const GatewaySensitivePromptDialog({
    required this.request,
    required this.onRespond,
    super.key,
  });

  @override
  State<GatewaySensitivePromptDialog> createState() =>
      _GatewaySensitivePromptDialogState();
}

class _GatewaySensitivePromptDialogState
    extends State<GatewaySensitivePromptDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _respond(String value) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onRespond(value);
      _controller.clear();
      if (mounted) {
        Navigator.of(context).pop(GatewaySensitivePromptDialogResult.responded);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = context.l10n.hermesDidNotAcceptResponse;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSudo = widget.request.kind == GatewaySensitivePromptKind.sudo;

    return AlertDialog(
      icon: Icon(isSudo ? Icons.lock_outline : Icons.key_outlined),
      title: Text(_localizedTitle(widget.request, context.l10n)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_localizedDescription(widget.request, context.l10n)),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sensitive-prompt-field'),
              controller: _controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_submitting,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: _localizedFieldLabel(widget.request, context.l10n),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) {
                if (value.isNotEmpty) _respond(value);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('sensitive-prompt-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              context.l10n.sensitiveValueNotice,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('sensitive-prompt-cancel'),
          onPressed: _submitting ? null : () => _respond(''),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('sensitive-prompt-send'),
          onPressed: _submitting || _controller.text.isEmpty
              ? null
              : () => _respond(_controller.text),
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.send),
        ),
      ],
    );
  }
}

/// Maps the client-side English defaults (used when the gateway omits these
/// fields) to the active locale. Gateway-provided values pass through.
String _localizedTitle(
  GatewaySensitivePromptRequest request,
  AppLocalizations l10n,
) {
  if (request.kind == GatewaySensitivePromptKind.sudo &&
      request.title == 'Administrator password needed') {
    return l10n.adminPasswordNeeded;
  }
  if (request.title == 'Secret needed') return l10n.secretNeeded;
  return request.title;
}

String _localizedDescription(
  GatewaySensitivePromptRequest request,
  AppLocalizations l10n,
) {
  if (request.kind == GatewaySensitivePromptKind.sudo &&
      request.description ==
          'Hermes needs a sudo password for the pending terminal command.') {
    return l10n.sudoPasswordDescription;
  }
  if (request.description == 'Hermes needs a secret for the pending skill.') {
    return l10n.secretDescription;
  }
  return request.description;
}

String _localizedFieldLabel(
  GatewaySensitivePromptRequest request,
  AppLocalizations l10n,
) {
  if (request.kind == GatewaySensitivePromptKind.sudo &&
      request.fieldLabel == 'Sudo password') {
    return l10n.sudoPasswordField;
  }
  if (request.fieldLabel == 'Secret value') return l10n.secretValueField;
  return request.fieldLabel;
}
