import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';
import 'package:kokonuts_bookkeeping/app/app_state_scope.dart';
import 'authenticated_image.dart';
import 'attachment_pdf_preview.dart';
import '../services/expenses_service.dart';

class ExpenseDetailsDialog extends StatefulWidget {
  const ExpenseDetailsDialog({super.key, required this.expense});

  final Expense expense;

  @override
  State<ExpenseDetailsDialog> createState() => _ExpenseDetailsDialogState();
}

class _ExpenseDetailsDialogState extends State<ExpenseDetailsDialog> {
  late Future<Expense> _future;
  final _expensesService = ExpensesService();
  bool _initialized = false;
  Map<String, String>? _apiHeaders;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetails();
      _initialized = true;
    }
  }

  Future<Expense> _loadDetails() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      throw const ExpensesException('Dialog no longer mounted');
    }

    if (token == null || token.trim().isEmpty) {
      throw const ExpensesException('You are not logged in.');
    }

    final headers = _buildAuthHeaders(appState, token);
    _apiHeaders = headers;

    return _expensesService.getExpense(
      id: widget.expense.id,
      headers: headers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<Expense>(
            future: _future,
            initialData: widget.expense,
            builder: (context, snapshot) {
              // Use initial data (list item) while loading, but specific data might be missing
              // Ideally, we show a loader or just show what we have.
              // The user asked to call the API to get more detailed info.
              // I will show the updated data when available.

              final expense = snapshot.data ?? widget.expense;
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              final hasError = snapshot.hasError;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DialogHeader(onClose: () => Navigator.of(context).pop()),
                  const SizedBox(height: 12),
                  if (hasError)
                    Padding(
                       padding: const EdgeInsets.only(bottom: 12),
                       child: Text('Failed to load details: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                    ),

                  if (isLoading && snapshot.data == null)
                     const Expanded(child: Center(child: CircularProgressIndicator())),

                  if (!isLoading || snapshot.data != null)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          _DetailField(
                            label: 'Expense category',
                            value: expense.categoryName,
                          ),
                          const SizedBox(height: 12),
                          _DetailField(label: 'Expense name', value: expense.name),
                          const SizedBox(height: 12),
                          _DetailField(
                            label: 'Created by',
                            value: expense.createdBy,
                          ),
                          const SizedBox(height: 20),
                          const Divider(thickness: 1.2),
                          const SizedBox(height: 20),
                          _DetailField(
                            label: 'Amount',
                            value: expense.formattedAmountWithoutCurrency,
                            valueStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DetailField(
                            label: 'Payment method',
                            value: expense.paymentMode,
                          ),
                          const SizedBox(height: 12),
                          _DetailField(
                            label: 'Expense date',
                            value: expense.formattedDate,
                          ),
                          const SizedBox(height: 12),
                          _AttachmentSection(
                            expense: expense,
                            apiHeaders: _apiHeaders,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Expense Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedValue = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(resolvedValue, style: valueStyle ?? theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({required this.expense, this.apiHeaders});

  final Expense expense;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    List<ExpenseAttachment> attachments = expense.attachments;
    if (attachments.isEmpty &&
        expense.receipt != null &&
        expense.receipt!.isNotEmpty) {
      // Fallback to create attachment from receipt URL
      attachments = [
        ExpenseAttachment(
          fileName: _extractFileName(expense.receipt!),
          downloadUrl: expense.receipt,
          uploadedBy: expense.createdBy,
        )
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachment',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (attachments.isEmpty)
          Text('No attachment available', style: theme.textTheme.bodyMedium)
        else
          Column(
            children: attachments
                .map(
                  (attachment) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ExpenseAttachmentCard(
                      attachment: attachment,
                      expenseId: expense.id,
                      apiHeaders: apiHeaders,
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        return segments.last;
      }
    } catch (_) {
      // ignore
    }
    return 'Attachment';
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: labelColor,
    );

    final displayValue = value.trim().isEmpty ? '—' : value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayValue,
              style: theme.textTheme.bodyMedium,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeAttachmentDownloadUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return trimmed;
  }

  if (uri.hasScheme) {
    return uri.toString();
  }

  final base = Uri.base;
  final canUseBase =
      base.hasScheme && (base.scheme == 'http' || base.scheme == 'https');
  if (canUseBase) {
    return base.resolveUri(uri).toString();
  }

  return uri.toString();
}

class _ExpenseAttachmentCard extends StatelessWidget {
  const _ExpenseAttachmentCard({
    required this.attachment,
    required this.expenseId,
    this.apiHeaders,
  });

  final ExpenseAttachment attachment;
  final String expenseId;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;

    final normalizedDownloadUrl = attachment.downloadUrl != null
        ? _normalizeAttachmentDownloadUrl(attachment.downloadUrl!)
        : null;

    // We use the special API URL for previewing
    // This URL requires 'authtoken' in headers, which is handled by _PreviewButton
    const baseUrl = 'https://crm.kokonuts.my/api/v1/expenses';
    final previewApiUrl = '$baseUrl/$expenseId/attachment';

    final previewType = _resolvePreviewType(attachment.fileName, normalizedDownloadUrl);

    final children = <Widget>[
      Row(
        children: [
          Icon(Icons.attach_file, color: labelColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.fileName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ];

    if (attachment.uploadedAt != null) {
       children.add(
        _LabelValueRow(
          label: 'Uploaded on',
          value: DateFormat.yMMMd().format(attachment.uploadedAt!),
        ),
      );
    }

    if (attachment.uploadedBy != null && attachment.uploadedBy!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(
          label: 'Uploaded by',
          value: attachment.uploadedBy!.trim(),
        ),
      );
    }

    if (attachment.sizeLabel != null && attachment.sizeLabel!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(
          label: 'Size',
          value: attachment.sizeLabel!.trim(),
        ),
      );
    }

    if (attachment.description != null && attachment.description!.trim().isNotEmpty) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          'Description',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(attachment.description!.trim(), style: theme.textTheme.bodyMedium),
      ]);
    }

    if (normalizedDownloadUrl != null) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          'Download URL',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          normalizedDownloadUrl,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ]);
    }

    if (previewType != null) {
      children.addAll([
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: _PreviewButton(
            fileName: attachment.fileName,
            downloadUrl: previewApiUrl,
            previewType: previewType,
            apiHeaders: apiHeaders,
          ),
        ),
      ]);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

enum _AttachmentPreviewType { image, pdf }

_AttachmentPreviewType? _resolvePreviewType(
  String fileName,
  String? downloadUrl,
) {
  if (_matchesExtension(fileName, _imageExtensions) ||
      _matchesExtension(downloadUrl, _imageExtensions)) {
    return _AttachmentPreviewType.image;
  }

  if (_matchesExtension(fileName, _pdfExtensions) ||
      _matchesExtension(downloadUrl, _pdfExtensions)) {
    return _AttachmentPreviewType.pdf;
  }

  return null;
}

const _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.bmp',
  '.webp',
  '.heic',
};

const _pdfExtensions = <String>{'.pdf'};

bool _matchesExtension(String? value, Set<String> extensions) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }

  bool match(String candidate) {
    final lower = candidate.toLowerCase();
    for (final ext in extensions) {
      final normalizedExt = ext.startsWith('.') ? ext : '.$ext';
      if (lower.endsWith(normalizedExt)) {
        return true;
      }
    }
    return false;
  }

  final trimmed = value.trim();
  if (match(trimmed)) {
    return true;
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && match(parsed.path)) {
    return true;
  }

  return false;
}

void _showAttachmentPreview({
  required BuildContext context,
  required String fileName,
  required String downloadUrl,
  required _AttachmentPreviewType previewType,
  Map<String, String>? apiHeaders,
}) {
  showDialog<void>(
    context: context,
    builder:
        (context) => _AttachmentPreviewDialog(
          fileName: fileName,
          downloadUrl: downloadUrl,
          previewType: previewType,
          apiHeaders: apiHeaders,
        ),
  );
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.fileName,
    required this.downloadUrl,
    required this.previewType,
    this.apiHeaders,
  });

  final String fileName;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    final title = '$fileName preview';
    final theme = Theme.of(context);
    Widget content;

    switch (previewType) {
      case _AttachmentPreviewType.image:
        content = _ImagePreview(
          downloadUrl: downloadUrl,
          apiHeaders: apiHeaders,
        );
        break;
      case _AttachmentPreviewType.pdf:
        content = _PdfPreview(downloadUrl: downloadUrl, apiHeaders: apiHeaders);
        break;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.downloadUrl, this.apiHeaders});

  final String downloadUrl;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: AuthenticatedImage(
          imageUrl: downloadUrl,
          headers: apiHeaders,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            // AuthenticatedImage handles loading internally or via this builder if provided,
            // but since it's async, the future builder handles the main loading state.
            // We can pass a simple placeholder here if needed, but the FutureBuilder in AuthenticatedImage
            // already shows a CircularProgressIndicator.
            // However, the API of AuthenticatedImage I wrote calls loadingBuilder if waiting.
            // Let's keep it simple.
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Unable to load image preview.'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({required this.downloadUrl, this.apiHeaders});

  final String downloadUrl;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    return buildAttachmentPdfPreview(downloadUrl, headers: apiHeaders);
  }
}

Map<String, String> _buildAuthHeaders(AppState appState, String token) {
  final rawToken = (appState.rawAuthToken ?? token).trim();
  final sanitizedToken = token
      .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
      .trim();
  final normalizedAuth = sanitizedToken.isNotEmpty
      ? 'Bearer $sanitizedToken'
      : token.trim();
  final autoTokenValue = rawToken
      .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
      .trim();
  final authtokenHeader = autoTokenValue.isNotEmpty
      ? autoTokenValue
      : sanitizedToken;
  return {
    'Accept': 'application/json',
    'authtoken': authtokenHeader,
    'Authorization': normalizedAuth,
  };
}

class _PreviewButton extends StatefulWidget {
  const _PreviewButton({
    required this.fileName,
    required this.downloadUrl,
    required this.previewType,
    this.apiHeaders,
  });

  final String fileName;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;
  final Map<String, String>? apiHeaders;

  @override
  State<_PreviewButton> createState() => _PreviewButtonState();
}

class _PreviewButtonState extends State<_PreviewButton> {
  bool _isLoading = false;

  Future<void> _onPressed() async {
    if (_isLoading) return;

    Map<String, String>? headers = widget.apiHeaders;

    if (headers == null || !headers.containsKey('authtoken')) {
      setState(() => _isLoading = true);
      try {
        final appState = AppStateScope.of(context);
        final token = await appState.getValidAuthToken();
        if (token != null && mounted) {
          headers = _buildAuthHeaders(appState, token);
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }

    if (!mounted) return;

    _showAttachmentPreview(
      context: context,
      fileName: widget.fileName,
      downloadUrl: widget.downloadUrl,
      previewType: widget.previewType,
      apiHeaders: headers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: _isLoading
          ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
          : const Icon(Icons.visibility),
      label: const Text('Preview'),
      onPressed: _onPressed,
    );
  }
}
