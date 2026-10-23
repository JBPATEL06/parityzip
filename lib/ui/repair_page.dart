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

class RepairPage extends StatefulWidget {
  const RepairPage({super.key});

  @override
  State<RepairPage> createState() => _RepairPageState();
}

class _RepairPageState extends State<RepairPage> {
  String? _selectedPar2Path;
  bool _isDragging = false;
  String? _errorMessage;
  String? _feedbackMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.watch<AppNavigationController>();
    if (nav.preselectedRepairFile != null &&
        nav.preselectedRepairFile != _selectedPar2Path) {
      _selectedPar2Path = nav.preselectedRepairFile;
      _errorMessage = null;
      nav.clearPreselectedRepairFile();
    }
  }

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

  Future<void> _startRepair(BuildContext context) async {
    if (_selectedPar2Path == null) return;

    final toolStatus = context.read<ToolStatus>();
    final jobController = context.read<JobController>();

    final par2Exe = toolStatus.par2.path ?? 'par2';
    await jobController.startRepairJob(
      par2Exe: par2Exe,
      par2FilePath: _selectedPar2Path!,
    );
  }

  Future<void> _handleCancel(BuildContext context) async {
    final jobController = context.read<JobController>();

    // Safety confirmation dialog per spec:
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel repair?'),
        content: const Text(
          'Stopping now may leave the file partly repaired. A backup of the damaged file is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continue repair'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop repair'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await jobController.cancel();
    }
  }

  void _openFolder(String filePath) {
    try {
      final parent = File(filePath).parent.path;
      Process.run('xdg-open', [parent]);
    } catch (_) {}
  }

  void _copyReport(RepairResult result) {
    final sb = StringBuffer();
    sb.writeln('=== ParityZip Repair Report ===');
    sb.writeln('Target PAR2: ${result.par2Path}');
    sb.writeln('Status: ${result.status.name}');
    if (result.repairedFileName != null) {
      sb.writeln('Repaired file: ${result.repairedFileName}');
    }
    if (result.backupFilePath != null) {
      sb.writeln('Backup file: ${result.backupFilePath}');
      if (result.backupFileSizeBytes != null) {
        sb.writeln('Backup size: ${result.backupFileSizeBytes} bytes');
      }
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    setState(() {
      _feedbackMessage = 'Repair report copied to clipboard.';
    });
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final toolStatus = context.watch<ToolStatus>();
    final jobController = context.watch<JobController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasPar2 = toolStatus.par2.isFound;
    final isRunning =
        jobController.isRunning &&
        jobController.currentJobType == JobType.repair;
    final repairResult = jobController.lastRepairResult;

    final canRepair =
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

          // Drop Zone
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
                    Icons.build_circle_outlined,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag & drop a .par2 file to repair',
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

            // Pre-repair disk safety info line
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Repair restores the original file and preserves a backup of the damaged file (.1). Ensure sufficient free disk space.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                ],
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
                'par2 tool is missing from PATH. Repair is disabled.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Repair Action Button
          FilledButton.icon(
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Repair'),
            onPressed: canRepair ? () => _startRepair(context) : null,
          ),
          const SizedBox(height: 16),

          // Pipeline Progress Card
          if (isRunning) ...[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jobController.stepLabel ?? 'Pipeline in progress...',
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
                          onPressed: () => _handleCancel(context),
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
          if (repairResult != null && !isRunning) ...[
            _buildRepairResultCard(context, repairResult),
            const SizedBox(height: 16),
          ],

          const LogPanel(),
        ],
      ),
    );
  }

  Widget _buildRepairResultCard(BuildContext context, RepairResult result) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final IconData icon;
    final Color iconColor;
    final String title;
    final String description;
    final Color cardBg;

    switch (result.status) {
      case RepairStatus.repairedAndVerified:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        title = 'Repaired and verified';
        description = 'All damaged blocks were successfully repaired, and the files passed post-repair verification.';
        cardBg = Colors.green.withValues(alpha: 0.1);
        break;

      case RepairStatus.nothingToRepair:
        icon = Icons.check_circle_outline;
        iconColor = Colors.green;
        title = 'Nothing to repair';
        description = 'All files are already healthy and intact.';
        cardBg = Colors.green.withValues(alpha: 0.1);
        break;

      case RepairStatus.cannotBeRepaired:
        icon = Icons.error_outline;
        iconColor = colorScheme.error;
        title = 'Cannot be repaired';
        description = 'Archive has damage exceeding the available recovery blocks. Repair is not possible.';
        cardBg = colorScheme.errorContainer.withValues(alpha: 0.2);
        break;

      case RepairStatus.cancelled:
        icon = Icons.warning_amber_rounded;
        iconColor = Colors.orange;
        title = 'Repair cancelled by user';
        description = 'The repair process was stopped. Any existing files and backups on disk were preserved.';
        cardBg = Colors.orange.withValues(alpha: 0.1);
        break;

      case RepairStatus.error:
        icon = Icons.error_outline;
        iconColor = colorScheme.error;
        title = 'Repair failed';
        description = result.errorMessage ?? 'An error occurred during repair.';
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

            // Backup file information if available
            if (result.backupFilePath != null) ...[
              const Divider(),
              const Text(
                'Damaged file backup preserved:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Location: ${result.backupFilePath}',
                style: const TextStyle(fontSize: 12),
              ),
              if (result.backupFileSizeBytes != null)
                Text(
                  'Size: ${_formatBytes(result.backupFileSizeBytes!)}',
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 8),
            ],

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
