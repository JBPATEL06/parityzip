import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/job_controller.dart';

class ProgressCard extends StatelessWidget {
  final VoidCallback? onCreateAnother;

  const ProgressCard({super.key, this.onCreateAnother});

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static void openFolder(String filePath) {
    final parent = File(filePath).parent.path;
    Process.run('xdg-open', [parent]);
  }

  @override
  Widget build(BuildContext context) {
    final jobController = context.watch<JobController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (jobController.isRunning) {
      final progress = jobController.progress;
      final message = jobController.statusMessage ?? 'Compressing...';

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(message, style: theme.textTheme.titleMedium),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel'),
                    onPressed: () => jobController.cancel(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
      );
    }

    if (jobController.cancelledNote != null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  jobController.cancelledNote!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Dismiss',
                onPressed: () => jobController.clearStatus(),
              ),
            ],
          ),
        ),
      );
    }

    final result = jobController.lastResult;
    if (result != null) {
      if (result.isSuccess) {
        final path = result.outputPath ?? '';
        final sizeText = result.outputSizeBytes != null
            ? formatBytes(result.outputSizeBytes!)
            : 'Unknown size';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: result.hasWarnings
              ? colorScheme.tertiaryContainer
              : colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.hasWarnings
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      color: result.hasWarnings
                          ? colorScheme.onTertiaryContainer
                          : colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.hasWarnings
                            ? 'Archive created with warnings'
                            : 'Archive created successfully',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: result.hasWarnings
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Dismiss',
                      onPressed: () => jobController.clearStatus(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText('File: $path'),
                const SizedBox(height: 4),
                Text('Format: ${result.format.label}'),
                const SizedBox(height: 4),
                Text('Size: $sizeText'),
                if (result.par2Summary != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Recovery data: ${result.par2Summary!.fileCount} files, ${formatBytes(result.par2Summary!.totalBytes)} (${result.par2Summary!.overheadPercent.toStringAsFixed(1)}% overhead)',
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        result.par2Verified == true
                            ? Icons.verified_outlined
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: result.par2Verified == true
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        result.par2Verified == true
                            ? 'Sanity check: Verified OK'
                            : 'Sanity check: Verification warning',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: result.par2Verified == true
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
                if (result.recoveryNote != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    result.recoveryNote!,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (result.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Warnings:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                  for (final warning in result.warnings)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text(
                        '• $warning',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onCreateAnother != null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Create another'),
                          onPressed: onCreateAnother,
                        ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open folder'),
                        onPressed: () => openFolder(path),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Compression failed',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Dismiss',
                      onPressed: () => jobController.clearStatus(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.errorMessage ?? 'An unexpected error occurred.',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ],
            ),
          ),
        );
      }
    }

    return const SizedBox.shrink();
  }
}
