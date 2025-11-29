// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

Widget createAttachmentPdfPreview(
  String downloadUrl, {
  Map<String, String>? headers,
}) {
  return _HtmlPdfPreview(downloadUrl: downloadUrl, headers: headers);
}

class _HtmlPdfPreview extends StatefulWidget {
  const _HtmlPdfPreview({required this.downloadUrl, this.headers});

  final String downloadUrl;
  final Map<String, String>? headers;

  @override
  State<_HtmlPdfPreview> createState() => _HtmlPdfPreviewState();
}

class _HtmlPdfPreviewState extends State<_HtmlPdfPreview> {
  late final String _viewType;
  html.IFrameElement? _iframe;
  String? _blobUrl;

  @override
  void initState() {
    super.initState();
    _viewType =
        'attachment-pdf-preview-${DateTime.now().microsecondsSinceEpoch}-${hashCode}';

    // Register the view factory immediately, but the src might be updated later if we need to fetch with headers
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      _iframe = html.IFrameElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'fullscreen'
        ..setAttribute('loading', 'lazy');

      // If no headers, use direct URL. If headers exist, we wait for _loadPdf to set src.
      if (widget.headers == null || widget.headers!.isEmpty) {
         _iframe!.src = widget.downloadUrl;
      }

      return _iframe!;
    });

    if (widget.headers != null && widget.headers!.isNotEmpty) {
      _loadPdf();
    }
  }

  @override
  void didUpdateWidget(covariant _HtmlPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.downloadUrl != oldWidget.downloadUrl || widget.headers != oldWidget.headers) {
       if (widget.headers != null && widget.headers!.isNotEmpty) {
          _revokeBlob();
          _loadPdf();
       } else {
          _revokeBlob();
          _iframe?.src = widget.downloadUrl;
       }
    }
  }

  @override
  void dispose() {
    _revokeBlob();
    super.dispose();
  }

  void _revokeBlob() {
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
  }

  Future<void> _loadPdf() async {
    try {
      final response = await http.get(
        Uri.parse(widget.downloadUrl),
        headers: widget.headers,
      );

      if (response.statusCode == 200) {
        final blob = html.Blob([response.bodyBytes], 'application/pdf');
        _blobUrl = html.Url.createObjectUrlFromBlob(blob);
        _iframe?.src = _blobUrl!;
      } else {
        // Fallback or error handling
        // For now, if fetch fails, maybe try direct load?
        _iframe?.src = widget.downloadUrl;
      }
    } catch (e) {
      // If error (e.g. CORS), fallback to direct URL
      _iframe?.src = widget.downloadUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
