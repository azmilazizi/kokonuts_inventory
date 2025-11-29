import 'package:flutter/widgets.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

Widget createAttachmentPdfPreview(
  String downloadUrl, {
  Map<String, String>? headers,
}) {
  return SfPdfViewer.network(downloadUrl, headers: headers);
}
