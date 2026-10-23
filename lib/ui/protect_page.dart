import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/input_selection.dart';
import '../core/models.dart';
import '../services/sevenzip_service.dart';
import '../state/job_controller.dart';
import 'widgets/log_panel.dart';
import 'widgets/progress_card.dart';

class ProtectPage extends StatefulWidget {
  const ProtectPage({super.key});

  @override
  State<ProtectPage> createState() => _ProtectPageState();
}

class _ProtectPageState extends State<ProtectPage> {
  final List<String> _selectedPaths = [];
  String? _outputDirectory;
  final TextEditingController _nameController = TextEditingController(
    text: 'archive',
  );
  CompressionLevel _compressionLevel = CompressionLevel.normal;
  bool _isDragging = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addPaths(List<String> paths) {
    if (paths.isEmpty) return;

    setState(() {
      for (final p in paths) {
        if (!_selectedPaths.contains(p)) {
          _selectedPaths.add(p);
        }
      }

      // If output directory is not yet chosen, default to common parent
      if (_outputDirectory == null && _selectedPaths.isNotEmpty) {
        _outputDirectory = InputSelection.getParentDir(_selectedPaths.first);
      }

      // If archive name is still default 'archive', suggest first item's name
      if (_nameController.text == 'archive' && _selectedPaths.isNotEmpty) {
        var base = InputSelection.getBaseName(_selectedPaths.first);
        final dotIndex = base.lastIndexOf('.');
        if (dotIndex > 0) {
          base = base.substring(0, dotIndex);
        }
        if (base.isNotEmpty) {
          _nameController.text = base;
        }
      }
    });
  }

  void _suggestNextName() {
    final current = _nameController.text.trim();
    final clean = current.endsWith('.7z')
        ? current.substring(0, current.length - 3)
        : current;
    final match = RegExp(r'^(.*?)(?:_(\d+))?$').firstMatch(clean);
    if (match != null) {
      final prefix = match.group(1) ?? 'archive';
      final numStr = match.group(2);
      final nextNum = (numStr != null ? int.parse(numStr) : 0) + 1;
      _nameController.text = '${prefix}_$nextNum';
    } else {
      _nameController.text = '${clean}_1';
    }
    setState(() {});
  }

  Future<void> _pickFiles() async {
    try {
      final files = await openFiles();
      if (files.isNotEmpty) {
        _addPaths(files.map((f) => f.path).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file picker: $e')),
        );
      }
    }
  }

  Future<void> _pickFolder() async {
    try {
      final folder = await getDirectoryPath();
      if (folder != null) {
        _addPaths([folder]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open folder picker: $e')),
        );
      }
    }
  }

  Future<void> _pickOutputFolder() async {
    try {
      final folder = await getDirectoryPath(initialDirectory: _outputDirectory);
      if (folder != null) {
        setState(() {
          _outputDirectory = folder;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open folder picker: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobController = context.watch<JobController>();
    final toolStatus = context.watch<ToolStatus>();
    final isRunning = jobController.isRunning;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selection = InputSelection(
      selectedPaths: _selectedPaths,
      outputDirectory: _outputDirectory,
      archiveName: _nameController.text,
    );

    final validation = selection.validate();
    final has7z = toolStatus.sevenZip.isFound;

    final lastSuccessPath = jobController.lastResult?.isSuccess == true
        ? jobController.lastResult?.outputPath
        : null;
    final isOutputFromCurrentJob =
        lastSuccessPath != null && validation.fullOutputPath == lastSuccessPath;

    final canCreate =
        has7z && validation.isValid && !isOutputFromCurrentJob && !isRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Drop Zone & Pickers
          DropTarget(
            onDragDone: (detail) {
              if (isRunning) return;
              _addPaths(detail.files.map((f) => f.path).toList());
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
                    Icons.archive_outlined,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drag & drop files or folders here',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.file_open, size: 18),
                        label: const Text('Add files'),
                        onPressed: isRunning ? null : _pickFiles,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.create_new_folder, size: 18),
                        label: const Text('Add folder'),
                        onPressed: isRunning ? null : _pickFolder,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Selected Items List
          if (_selectedPaths.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Selected items (${_selectedPaths.length})',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: isRunning
                      ? null
                      : () => setState(() => _selectedPaths.clear()),
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _selectedPaths.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final path = _selectedPaths[index];
                  final isDir = Directory(path).existsSync();
                  final name = InputSelection.getBaseName(path);
                  final parent = InputSelection.getParentDir(path);
                  final firstParent = InputSelection.getParentDir(
                    _selectedPaths.first,
                  );
                  final hasFolderConflict = parent != firstParent;

                  return ListTile(
                    dense: true,
                    tileColor: hasFolderConflict
                        ? colorScheme.errorContainer.withValues(alpha: 0.3)
                        : null,
                    leading: Icon(
                      hasFolderConflict
                          ? Icons.warning_amber_rounded
                          : (isDir ? Icons.folder : Icons.insert_drive_file),
                      color: hasFolderConflict ? colorScheme.error : null,
                      size: 20,
                    ),
                    title: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: hasFolderConflict
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: hasFolderConflict ? colorScheme.error : null,
                      ),
                    ),
                    subtitle: Text(
                      hasFolderConflict ? 'In different folder: $parent' : path,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: hasFolderConflict
                            ? colorScheme.error
                            : theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Remove',
                      onPressed: isRunning
                          ? null
                          : () {
                              setState(() {
                                _selectedPaths.removeAt(index);
                              });
                            },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 3. Destination folder and archive name
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Output settings', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Destination folder',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _outputDirectory ?? 'No folder selected',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: _outputDirectory == null
                                    ? colorScheme.error
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Browse...'),
                        onPressed: isRunning ? null : _pickOutputFolder,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    enabled: !isRunning,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Archive name',
                      suffixText: '.7z',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. Compression level
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Compression level', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  SegmentedButton<CompressionLevel>(
                    segments: const [
                      ButtonSegment(
                        value: CompressionLevel.fast,
                        label: Text('Fast'),
                      ),
                      ButtonSegment(
                        value: CompressionLevel.normal,
                        label: Text('Normal'),
                      ),
                      ButtonSegment(
                        value: CompressionLevel.maximum,
                        label: Text('Maximum'),
                      ),
                    ],
                    selected: {_compressionLevel},
                    onSelectionChanged: isRunning
                        ? null
                        : (newSelection) {
                            setState(() {
                              _compressionLevel = newSelection.first;
                            });
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 5. Recovery data (disabled, coming in M3)
          Card(
            margin: EdgeInsets.zero,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recovery data',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.disabledColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: const Text(
                          'Coming in M3',
                          style: TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recovery data: 10% (Roughly this much damage can be repaired)',
                    style: TextStyle(fontSize: 12, color: theme.disabledColor),
                  ),
                  const SizedBox(height: 8),
                  Slider(value: 10, min: 5, max: 30, onChanged: null),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Validation / Error explanation / Success status hint
          if (!has7z) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Cannot create archive: 7-Zip CLI tool (7z) is missing from PATH.',
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ),
          ] else if (isOutputFromCurrentJob) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Archive created: ${InputSelection.getBaseName(lastSuccessPath)}. Change name to create another.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.drive_file_rename_outline, size: 14),
                    label: const Text('New name'),
                    onPressed: _suggestNextName,
                  ),
                ],
              ),
            ),
          ] else if (!validation.isValid && _selectedPaths.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validation.errorMessage!,
                      style: TextStyle(color: colorScheme.error, fontSize: 13),
                    ),
                  ),
                  if (validation.errorMessage!.contains('parent folder')) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear list'),
                      onPressed: isRunning
                          ? null
                          : () => setState(() => _selectedPaths.clear()),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 6. Primary Action Button
          FilledButton.icon(
            icon: const Icon(Icons.archive),
            label: const Text('Create archive'),
            onPressed: canCreate
                ? () {
                    jobController.startCompression(
                      exe: toolStatus.sevenZip.path!,
                      validation: validation,
                      level: _compressionLevel,
                    );
                  }
                : null,
          ),
          const SizedBox(height: 16),

          // 7. Progress & Results
          const ProgressCard(),
          const SizedBox(height: 16),

          // 8. Log Panel
          const LogPanel(),
        ],
      ),
    );
  }
}
