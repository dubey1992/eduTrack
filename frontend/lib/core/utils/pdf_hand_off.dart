import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'file_saver.dart';

/// Hands a PDF to the person: the phone's share sheet (save to Files, send
/// on WhatsApp), or a download in a browser - a parent's receipts and report
/// cards, an employee's payslip (docs/mobile-apps-review.md, 6.7). Swappable
/// in tests.
typedef PdfHandOff = Future<void> Function(List<int> bytes, String fileName);

final pdfHandOffProvider = Provider<PdfHandOff>(
  (ref) => (bytes, fileName) async {
    if (kIsWeb) {
      saveBytes(fileName: fileName, bytes: bytes, mimeType: 'application/pdf');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'application/pdf', name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  },
);
