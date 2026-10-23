import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yaru/yaru.dart';

import '../../state/log_controller.dart';

class LogPanel extends StatefulWidget {
  final LogController? logController;

  const LogPanel({super.key, this.logController});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.logController ?? context.watch<LogController>();
    final theme = Theme.of(context);
    final text = controller.fullText;

    return YaruExpandable(
      isExpanded: _isExpanded,
      onChange: (expanded) {
        setState(() {
          _isExpanded = expanded;
        });
      },
      header: Row(
        children: [
          Text(
            'Log (${controller.lineCount} lines)',
            style: theme.textTheme.titleSmall,
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy log'),
            onPressed: controller.lineCount == 0
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Log copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          reverse: true,
          child: SelectableText(
            text.isEmpty ? 'No log entries yet.' : text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
