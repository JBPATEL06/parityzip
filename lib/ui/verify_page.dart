import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../services/par2_service.dart';
import '../state/job_controller.dart';
import '../state/navigation_controller.dart';
import 'widgets/log_panel.dart';

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key});

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  String? _selectedPar2Path;
  bool _isDragging = false;
  String? _errorMessage;
  String? _feedbackMessage;

  void _onFileSelected(String path) {
    setState(() {
      _errorMessage = null;
      _feedbackMessage = null;
    });

    final validation = Par2Service.validatePar2Input(path);
    if (!validation.isValid) {
      setState(() {
        _errorMessage = validation.errorMessage;
      });
      return;
    }

    setState(() {
      _selectedPar2Path = path;
      _errorMessage = null;
    });
  }

  Future<void> _pickFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'PAR2 Recovery files',
        extensions: ['par2'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file != null) {
        _onFileSelected(file.path);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not open file: $e';
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedPar2Path = null;
      _errorMessage = null;
      _feedbackMessage = null;
    });
  }

  Future<void> _startVerify(BuildContext context) async {
    if (_selectedPar2Path == null) return;

    final toolStatus = context.read<ToolStatus>();
    final jobController = context.read<JobController>();

    final par2Exe = toolStatus.par2.path ?? 'par2';
    await jobController.startVerifyJob(
      par2Exe: par2Exe,
      par2FilePath: _selectedPar2Path!,
    );
  }

  void _openFolder(String filePath) {
    try {
      final parent = File(filePath).parent.path;
      Process.run('xdg-open', [parent]);
    } catch (_) {}
  }

  void _copyReport(VerifyResult result) {
    final sb = StringBuffer();
    sb.writeln('=== ParityZip Verification Report ===');
    sb.writeln('File: ${result.par2Path}');
    sb.writeln('Status: ${result.state.name}');
    if (result.report.files.isNotEmpty) {
      sb.writeln('Target files:');
      for (final f in result.report.files) {
        sb.writeln(' - ${f.fileName}: ${f.status.name}');
      }
    }
    if (result.report.availableBlocks != null &&
        result.report.totalBlocks != null) {
      sb.writeln(
        'Data blocks: ${result.report.availableBlocks} / ${result.report.totalBlocks}',
      );
    }
    if (result.report.recoveryBlocksAvailable != null) {
      sb.writeln(
        'Recovery blocks available: ${result.report.recoveryBlocksAvailable}',
      );
    }
    if (result.report.recoveryBlocksNeeded != null) {
      sb.writeln(
        'Recovery blocks needed: ${result.report.recoveryBlocksNeeded}',
      );
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    setState(() {
      _feedbackMessage = 'Report copied to clipboard.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final toolStatus = context.watch<ToolStatus>();
    final jobController = context.watch<JobController>();
    final nav = context.watch<AppNavigationController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasPar2 = toolStatus.par2.isFound;
    final isRunning =
        jobController.isRunning &&
        jobController.currentJobType == JobType.verify;
    final verifyResult = jobController.lastVerifyResult;

    final canVerify =
        hasPar2 && _selectedPar2Path != null && !jobController.isRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Feedback Banner
          if (_feedbackMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _feedbackMessage!,
                      style: TextStyle(color: colorScheme.onPrimaryContainer),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _feedbackMessage = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Error Banner
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _errorMessage = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Drop Zone & File Selection
          DropTarget(
            onDragDone: (detail) {
              if (jobController.isRunning) return;
              if (detail.files.isNotEmpty) {
                final dropped = detail.files.first.path;
                _onFileSelected(dropped);
              }
            },
            onDragEntered: (_) => setState(() => _isDragging = true),
            onDragExited: (_) => setState(() => _isDragging = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: _isDragging
                    ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDragging
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: _isDragging ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag & drop a .par2 file here',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accepts .par2 index file or any .vol*.par2 volume',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.file_open, size: 18),
                    label: const Text('Choose .par2 file'),
                    onPressed: jobController.isRunning ? null : _pickFile,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Selected File Card
          if (_selectedPar2Path != null) ...[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.description, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            File(_selectedPar2Path!).path.split('/').last,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!jobController.isRunning)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Clear selection',
                            onPressed: _clearSelection,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Full path: $_selectedPar2Path',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Protected folder: ${File(_selectedPar2Path!).parent.path}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Missing tool notice
          if (!hasPar2) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'par2 tool is missing from PATH. Verification is disabled.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Verify Action Button
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Verify'),
            onPressed: canVerify ? () => _startVerify(context) : null,
          ),
          const SizedBox(height: 16),

          // Progress Card
          if (isRunning) ...[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jobController.stepLabel ?? 'Verifying...',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (jobController.progress != null)
                      LinearProgressIndicator(value: jobController.progress)
                    else
                      const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          jobController.statusMessage ?? '',
                          style: const TextStyle(fontSize: 12),
                        ),
                        TextButton(
                          onPressed: () => jobController.cancel(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Result Card
          if (verifyResult != null && !isRunning) ...[
            _buildResultCard(context, verifyResult, nav),
            const SizedBox(height: 16),
          ],

          const LogPanel(),
        ],
      ),
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    VerifyResult result,
    AppNavigationController nav,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final IconData icon;
    final Color iconColor;
    final String title;
    final String description;
    final Color cardBg;

    switch (result.state) {
      case Par2VerifyState.ok:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        title = 'All files are correct, repair is not required';
        description = 'All protected files in this folder are completely intact and verified.';
        cardBg = Colors.green.withValues(alpha: 0.1);
        break;

      case Par2VerifyState.damagedRepairable:
        icon = Icons.warning_amber_rounded;
        iconColor = Colors.orange;
        title = 'Archive is damaged but repairable';
        description = 'Data damage detected. Recovery data has sufficient redundancy to restore all files.';
        cardBg = Colors.orange.withValues(alpha: 0.1);
        break;

      case Par2VerifyState.damagedNotRepairable:
        icon = Icons.error_outline;
        iconColor = colorScheme.error;
        title = 'Archive is damaged and cannot be repaired';
        description = 'Damage exceeds the available recovery blocks. The file cannot be restored.';
        cardBg = colorScheme.errorContainer.withValues(alpha: 0.2);
        break;

      case Par2VerifyState.insufficientData:
        icon = Icons.broken_image_outlined;
        iconColor = colorScheme.error;
        title = 'Recovery data incomplete';
        description =
            'Essential PAR2 recovery packets are missing or corrupted.';
        cardBg = colorScheme.errorContainer.withValues(alpha: 0.2);
        break;

      case Par2VerifyState.error:
        icon = Icons.error_outline;
        iconColor = colorScheme.error;
        title = 'Verification error';
        description =
            result.errorMessage ?? 'An error occurred during verification.';
        cardBg = colorScheme.errorContainer.withValues(alpha: 0.2);
        break;
    }

    return Card(
      margin: EdgeInsets.zero,
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Per-file status list
            if (result.report.files.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Files in recovery set:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...result.report.files.map((file) {
                final IconData fIcon;
                final Color fColor;
                final String statusLabel;

                switch (file.status) {
                  case Par2TargetFileStatus.found:
                    fIcon = Icons.check;
                    fColor = Colors.green;
                    statusLabel = 'Intact';
                    break;
                  case Par2TargetFileStatus.damaged:
                    fIcon = Icons.warning_amber;
                    fColor = Colors.orange;
                    statusLabel =
                        file.availableBlocks != null && file.totalBlocks != null
                        ? 'Damaged (${file.availableBlocks}/${file.totalBlocks} blocks)'
                        : 'Damaged';
                    break;
                  case Par2TargetFileStatus.missing:
                    fIcon = Icons.close;
                    fColor = Colors.red;
                    statusLabel = 'Missing';
                    break;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(fIcon, size: 16, color: fColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.fileName,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        statusLabel,
                        style: TextStyle(fontSize: 12, color: fColor),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (result.state == Par2VerifyState.damagedRepairable)
                  FilledButton.icon(
                    icon: const Icon(Icons.build_circle_outlined, size: 18),
                    label: const Text('Go to Repair'),
                    onPressed: () {
                      nav.goToRepair(result.par2Path);
                    },
                  ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Open folder'),
                  onPressed: () => _openFolder(result.par2Path),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy report'),
                  onPressed: () => _copyReport(result),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
