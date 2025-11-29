import 'package:flutter/widgets.dart';

import 'attachment_pdf_preview_io.dart'
    if (dart.library.html) 'attachment_pdf_preview_web.dart';

Widget buildAttachmentPdfPreview(
  String downloadUrl, {
  Map<String, String>? headers,
}) {
  return createAttachmentPdfPreview(downloadUrl, headers: headers);
}
