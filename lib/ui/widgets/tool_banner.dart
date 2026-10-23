import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';

class ToolBanner extends StatefulWidget {
  final ToolStatus? toolStatus;
  final VoidCallback? onDismissed;

  const ToolBanner({super.key, this.toolStatus, this.onDismissed});

  @override
  State<ToolBanner> createState() => _ToolBannerState();
}

class _ToolBannerState extends State<ToolBanner> {
  bool _dismissed = false;

  static const String installCommand = 'sudo apt install p7zip-full par2';

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return const SizedBox.shrink();
    }

    final status = widget.toolStatus ?? context.watch<ToolStatus>();
    if (status.allFound) {
      return const SizedBox.shrink();
    }

    final missing = status.missingTools;
    final missingLabel = missing.length > 1
        ? 'Missing required tools: ${missing.join(', ')}'
        : 'Missing required tool: ${missing.first}';

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      missingLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                installCommand,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ],
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: installCommand));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Command copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Dismiss',
                onPressed: () {
                  setState(() {
                    _dismissed = true;
                  });
                  widget.onDismissed?.call();
                },
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}
