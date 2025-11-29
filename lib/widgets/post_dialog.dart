import 'dart:convert';

import 'package:flutter/material.dart';

/// Lightweight dialog that showcases the POST endpoint for creating records.
class PostDialog extends StatelessWidget {
  const PostDialog({
    super.key,
    required this.title,
    required this.apiPath,
    required this.samplePayload,
    this.description,
  });

  final String title;
  final String apiPath;
  final Map<String, dynamic> samplePayload;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prettyPayload = const JsonEncoder.withIndent('  ').convert(samplePayload);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null) ...[
            Text(description!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],
          Text('Endpoint', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(apiPath, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Text('Sample payload', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              prettyPayload,
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
