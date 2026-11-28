import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/date_format.dart';
import 'offline_fee_counter.dart';

/// The slip a fee counter hands over while the internet is down
/// (docs/offline-web.md, O4): made on the computer, numbered `P-<code>-<n>`,
/// and plain that the school's own numbered receipt follows.
///
/// Amounts carry the currency code ("INR 3,500.00") rather than a symbol:
/// the PDF's built-in font, the one available with no connection, has no ₹.
Future<Uint8List> provisionalReceiptPdf(TakenPayment payment) {
  final doc = pw.Document(title: 'Provisional receipt ${payment.provisionalNumber}', author: payment.school.name);
  const ink = PdfColor.fromInt(0xFF1F2A44);
  const muted = PdfColor.fromInt(0xFF5B6478);
  const line = PdfColor.fromInt(0xFFD9DEE8);
  const band = PdfColor.fromInt(0xFFF3F5F9);
  const accent = PdfColor.fromInt(0xFFB45309);

  final school = payment.school;
  final contact = [school.address, school.phone, school.email].where((part) => part.isNotEmpty).join('  ·  ');

  pw.Widget labelled(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 92,
          child: pw.Text(label, style: const pw.TextStyle(color: muted, fontSize: 9)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(color: ink, fontSize: 10)),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            school.name,
            style: pw.TextStyle(color: ink, fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          if (contact.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(contact, style: const pw.TextStyle(color: muted, fontSize: 8.5)),
            ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const pw.BoxDecoration(color: band),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'PROVISIONAL RECEIPT',
                  style: pw.TextStyle(color: accent, fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 1),
                ),
                pw.Text(
                  payment.provisionalNumber,
                  style: pw.TextStyle(color: ink, fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          labelled('Received from', payment.student.guardianName ?? payment.student.name),
          labelled('Student', payment.student.name),
          labelled('Admission no.', [payment.student.admissionNumber, ?payment.student.className].join('  ·  ')),
          labelled('Taken on', formatDateTime(payment.takenAt)),
          labelled(
            'Paid by',
            payment.mode == OfflineFeeMode.cheque && payment.reference != null
                ? 'Cheque no. ${payment.reference}'
                : payment.mode.label,
          ),
          if (payment.note != null && payment.note!.isNotEmpty) labelled('Note', payment.note!),
          pw.SizedBox(height: 10),
          pw.Table(
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.6)),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1.6)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: ink, width: 0.8)),
                ),
                children: [
                  _cell('Fee', header: true),
                  _cell('Due', header: true),
                  _cell('Amount', header: true, right: true),
                ],
              ),
              for (final part in payment.parts)
                pw.TableRow(
                  children: [
                    _cell('${part.due.feeHead} - ${part.due.label}\n${part.due.academicYear}'),
                    _cell(formatIsoDate(part.due.dueDate)),
                    _cell(pdfMoney(part.amount, part.due.currencyCode), right: true),
                  ],
                ),
            ],
          ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: ink, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total received',
                  style: pw.TextStyle(color: ink, fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  pdfMoney(payment.total, payment.currencyCode),
                  style: pw.TextStyle(color: ink, fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: 0.8)),
            child: pw.Text(
              'Taken while the school\'s internet was down. The school\'s numbered receipt follows once the '
              'payment is recorded. Please keep this slip until then.',
              style: const pw.TextStyle(color: muted, fontSize: 8.5),
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Received by ${payment.takenBy}', style: const pw.TextStyle(color: muted, fontSize: 9)),
              pw.Column(
                children: [
                  pw.Container(width: 120, height: 0.6, color: muted),
                  pw.SizedBox(height: 3),
                  pw.Text('Signature', style: const pw.TextStyle(color: muted, fontSize: 8)),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

pw.Widget _cell(String text, {bool header = false, bool right = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 2),
  child: pw.Text(
    text,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(
      fontSize: header ? 8.5 : 9.5,
      color: header ? const PdfColor.fromInt(0xFF5B6478) : const PdfColor.fromInt(0xFF1F2A44),
      fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

/// "INR 3,500.00".
String pdfMoney(double amount, String currencyCode) => '$currencyCode ${NumberFormat('#,##0.00').format(amount)}';
