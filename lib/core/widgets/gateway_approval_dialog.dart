import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../models/gateway_approval.dart';

typedef ApprovalResponder = Future<void> Function(GatewayApprovalChoice choice);

class GatewayApprovalDialog extends StatefulWidget {
  final GatewayApprovalRequest request;
  final ApprovalResponder onRespond;

  const GatewayApprovalDialog({
    required this.request,
    required this.onRespond,
    super.key,
  });

  @override
  State<GatewayApprovalDialog> createState() => _GatewayApprovalDialogState();
}

class _GatewayApprovalDialogState extends State<GatewayApprovalDialog> {
  GatewayApprovalChoice? _submitting;
  bool _confirmAlways = false;
  String? _error;

  Future<void> _respond(GatewayApprovalChoice choice) async {
    if (_submitting != null) return;
    if (choice == GatewayApprovalChoice.always && !_confirmAlways) {
      setState(() {
        _confirmAlways = true;
        _error = null;
      });
      return;
    }

    setState(() {
      _submitting = choice;
      _error = null;
    });
    try {
      await widget.onRespond(choice);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = null;
        _error = context.l10n.couldNotSendApproval(error.toString());
      });
    }
  }

  String _labelFor(GatewayApprovalChoice choice) {
    return switch (choice) {
      GatewayApprovalChoice.once => context.l10n.allowOnce,
      GatewayApprovalChoice.session => context.l10n.allowForSession,
      GatewayApprovalChoice.always =>
        _confirmAlways ? context.l10n.confirmAlwaysAllow : context.l10n.alwaysAllow,
      GatewayApprovalChoice.deny => context.l10n.deny,
    };
  }

  String _scopeFor(GatewayApprovalChoice choice) {
    return switch (choice) {
      GatewayApprovalChoice.once => context.l10n.runOnlyThisCommand,
      GatewayApprovalChoice.session =>
        context.l10n.allowMatchingCommands,
      GatewayApprovalChoice.always =>
        context.l10n.savePermanentRule,
      GatewayApprovalChoice.deny => context.l10n.doNotRunCommand,
    };
  }

  IconData _iconFor(GatewayApprovalChoice choice) {
    return switch (choice) {
      GatewayApprovalChoice.once => Icons.play_arrow_rounded,
      GatewayApprovalChoice.session => Icons.timer_outlined,
      GatewayApprovalChoice.always => Icons.verified_user_outlined,
      GatewayApprovalChoice.deny => Icons.block_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final busy = _submitting != null;

    return AlertDialog(
      icon: const Icon(Icons.gpp_maybe_outlined),
      title: Text(context.l10n.approvalNeeded),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(request.description ==
                      'Hermes wants to run a command.'
                  ? context.l10n.approvalFallbackDescription
                  : request.description),
              if (request.command.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(context.l10n.command, style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    request.command,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              if (_confirmAlways) ...[
                const SizedBox(height: 14),
                Text(
                  context.l10n.permanentRuleWarning,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  key: const Key('approval-error'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              for (final choice in request.choices) ...[
                OutlinedButton.icon(
                  key: Key('approval-${choice.wireValue}'),
                  onPressed: busy ? null : () => _respond(choice),
                  icon: _submitting == choice
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_iconFor(choice)),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_labelFor(choice)),
                        Text(
                          _scopeFor(choice),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  style: choice == GatewayApprovalChoice.deny
                      ? OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
