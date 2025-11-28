import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Set<String> allowedAttachmentExtensions = {
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'gif',
  'bmp',
  'heic',
  'webp',
};

bool isAllowedAttachmentExtension(String? extension) {
  final sanitized = extension?.toLowerCase();
  if (sanitized == null || sanitized.isEmpty) {
    return false;
  }
  return allowedAttachmentExtensions.contains(sanitized);
}

String? attachmentExtension(String name) {
  final index = name.lastIndexOf('.');
  if (index == -1 || index == name.length - 1) {
    return null;
  }
  return name.substring(index + 1).toLowerCase();
}

class AttachmentPicker extends StatefulWidget {
  const AttachmentPicker({
    this.label,
    required this.description,
    required this.files,
    required this.onPick,
    required this.onFilesSelected,
    required this.onFileRemoved,
  });

  final String? label;
  final String description;
  final List<PlatformFile> files;
  final VoidCallback onPick;
  final ValueChanged<List<PlatformFile>> onFilesSelected;
  final ValueChanged<PlatformFile> onFileRemoved;

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  bool _isDragging = false;
  bool _isProcessingDrop = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const iconSize = 24.0;
    final borderColor = _isDragging
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final surfaceColor =
        _isDragging ? theme.colorScheme.primary.withOpacity(0.08) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null && widget.label!.isNotEmpty) ...[
          Text(widget.label!, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: _handleDrop,
          child: InkWell(
            onTap: widget.onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.2),
                color: surfaceColor,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 520;

                  final descriptionSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.description,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      if (widget.files.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.files
                              .map(
                                (file) => SelectedFileChip(
                                  file: file,
                                  onClear: () => widget.onFileRemoved(file),
                                ),
                              )
                              .toList(),
                        )
                      else
                        Text(
                          'No files selected. Drag and drop here or tap to choose.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      if (_isProcessingDrop) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Processing dropped file...',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ],
                  );

                  final browseButton = OutlinedButton.icon(
                    onPressed: widget.onPick,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse files'),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _isDragging
                                  ? Icons.file_upload
                                  : Icons.attach_file,
                              color: theme.colorScheme.primary,
                              size: iconSize,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: descriptionSection),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: iconSize + 12),
                          child: browseButton,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isDragging ? Icons.file_upload : Icons.attach_file,
                        color: theme.colorScheme.primary,
                        size: iconSize,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            descriptionSection,
                            const SizedBox(height: 12),
                            browseButton,
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleDrop(DropDoneDetails details) {
    if (details.files.isEmpty) {
      setState(() => _isDragging = false);
      return;
    }

    setState(() {
      _isDragging = false;
      _isProcessingDrop = true;
    });

    Future.wait(
      details.files
          .where((file) =>
              isAllowedAttachmentExtension(attachmentExtension(file.name)))
          .map(_convertFile),
    ).then((files) {
      if (!mounted) {
        return;
      }
      final validFiles = files.whereType<PlatformFile>().toList();
      if (validFiles.isNotEmpty) {
        widget.onFilesSelected([...widget.files, ...validFiles]);
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() => _isProcessingDrop = false);
      }
    });
  }

  Future<PlatformFile?> _convertFile(XFile xfile) async {
    if (!isAllowedAttachmentExtension(attachmentExtension(xfile.name))) {
      return null;
    }
    try {
      final size = await xfile.length();
      final bytes = kIsWeb ? await xfile.readAsBytes() : null;
      return PlatformFile(
        name: xfile.name,
        size: size,
        path: xfile.path,
        readStream: kIsWeb ? null : xfile.openRead(),
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }
}

class SelectedFileChip extends StatelessWidget {
  const SelectedFileChip({required this.file, required this.onClear});

  final PlatformFile file;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeLabel = _formatBytes(file.size);
    final truncatedName = _truncateFileName(file.name);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceVariant,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 18),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              '$truncatedName ($sizeLabel)',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Remove attachment',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[suffixIndex]}';
  }

  String _truncateFileName(String name, {int maxLength = 32}) {
    if (name.length <= maxLength) {
      return name;
    }

    final dotIndex = name.lastIndexOf('.');
    final extension = dotIndex != -1 ? name.substring(dotIndex) : '';
    final remainingLength = maxLength - extension.length - 3;

    if (remainingLength <= 0) {
      return '${name.substring(0, maxLength - 3)}...';
    }

    return '${name.substring(0, remainingLength)}...$extension';
  }
}
