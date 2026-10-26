import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/system_info.dart';

class ParityZipAboutDialog extends StatefulWidget {
  final ToolStatus toolStatus;

  const ParityZipAboutDialog({super.key, required this.toolStatus});

  static Future<void> show(BuildContext context, ToolStatus toolStatus) {
    return showDialog(
      context: context,
      builder: (ctx) => ParityZipAboutDialog(toolStatus: toolStatus),
    );
  }

  @override
  State<ParityZipAboutDialog> createState() => _ParityZipAboutDialogState();
}

class _ParityZipAboutDialogState extends State<ParityZipAboutDialog> {
  String _osName = '';
  String _sevenZipVersion = 'Detecting...';
  String _par2Version = 'Detecting...';
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final os = SystemInfo.getOsName();
    final sevenZip = await SystemInfo.getToolVersion(
      widget.toolStatus.sevenZip.path,
    );
    final par2 = await SystemInfo.getToolVersion(widget.toolStatus.par2.path);

    if (mounted) {
      setState(() {
        _osName = os;
        _sevenZipVersion = sevenZip;
        _par2Version = par2;
      });
    }
  }

  void _copyDetails() {
    final text = SystemInfo.formatDiagnosticDetails(
      osName: _osName,
      sevenZipPath: widget.toolStatus.sevenZip.path ?? 'Not found',
      sevenZipVersion: _sevenZipVersion,
      par2Path: widget.toolStatus.par2.path ?? 'Not found',
      par2Version: _par2Version,
    );
    Clipboard.setData(ClipboardData(text: text));
    _copiedTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      title: Row(
        children: [
          Image.asset(
            'assets/app_icon_64.png',
            width: 44,
            height: 44,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.archive_outlined,
              size: 44,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SystemInfo.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'v${SystemInfo.appVersion} • ${SystemInfo.licenseId} License',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'A native Linux desktop application combining 7-Zip compression and PAR2 recovery data creation, verification, and repair.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                SystemInfo.repositoryUrl,
                style: TextStyle(
                  color: colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
              const Divider(height: 24),
              Text(
                'Environment & Helper Tools',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('OS', _osName.isNotEmpty ? _osName : 'Linux'),
              const SizedBox(height: 6),
              _buildDetailRow(
                '7-Zip CLI',
                widget.toolStatus.sevenZip.path ?? 'Missing',
                subtitle: _sevenZipVersion,
              ),
              const SizedBox(height: 6),
              _buildDetailRow(
                'PAR2 CLI',
                widget.toolStatus.par2.path ?? 'Missing',
                subtitle: _par2Version,
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
          label: Text(_copied ? 'Copied!' : 'Copy details'),
          onPressed: _copyDetails,
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {String? subtitle}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$label: ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            SelectableText(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
