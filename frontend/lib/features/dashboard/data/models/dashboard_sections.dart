/// The dashboard's two summaries added with the enhancement
/// (docs/dashboard.md): today's fee receipts per person who took them, and
/// this month's SMS and WhatsApp by the status the message log keeps.
///
/// Both arrive already worked out and formatted by the server, which owns
/// the money rules (one currency per line, never blended) and the gates
/// (each is null for anybody who may not open the screen behind it).
library;

class CollectionsToday {
  const CollectionsToday({
    required this.date,
    required this.receipts,
    required this.cancelledReceipts,
    required this.collected,
    required this.byStaff,
  });

  factory CollectionsToday.fromJson(Map<String, dynamic> json) {
    return CollectionsToday(
      date: json['date'] as String,
      receipts: json['receipts'] as int? ?? 0,
      cancelledReceipts: json['cancelled_receipts'] as int? ?? 0,
      collected: (json['collected'] as List<dynamic>? ?? const []).cast<String>(),
      byStaff: (json['by_staff'] as List<dynamic>? ?? const [])
          .map((line) => StaffCollection.fromJson(line as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The school's date, `YYYY-MM-DD`.
  final String date;
  final int receipts;
  final int cancelledReceipts;

  /// One formatted amount per currency, e.g. ["INR 3,950.00"].
  final List<String> collected;
  final List<StaffCollection> byStaff;
}

class StaffCollection {
  const StaffCollection({
    required this.receivedById,
    required this.receivedBy,
    required this.receipts,
    required this.amount,
    required this.cash,
    required this.credit,
    required this.hasCredit,
  });

  factory StaffCollection.fromJson(Map<String, dynamic> json) {
    return StaffCollection(
      receivedById: json['received_by_id'] as int?,
      receivedBy: json['received_by'] as String? ?? 'Not recorded',
      receipts: json['receipts'] as int? ?? 0,
      amount: json['amount_display'] as String? ?? '',
      cash: json['cash_display'] as String? ?? '',
      credit: json['credit_display'] as String? ?? '',
      hasCredit: (double.tryParse('${json['credit_amount']}') ?? 0) > 0,
    );
  }

  /// Null for receipts recorded before the app kept who took them.
  final int? receivedById;
  final String receivedBy;
  final int receipts;
  final String amount;

  /// The part paid in cash - what this person has to hand over.
  final String cash;

  /// The part of [amount] kept as credit for families: an advance, paid
  /// ahead of anything owed. Inside [amount], never added to it.
  final String credit;
  final bool hasCredit;
}

class MessagesThisMonth {
  const MessagesThisMonth({
    required this.month,
    required this.total,
    required this.channels,
    required this.feeRelated,
    required this.providerDelivers,
  });

  factory MessagesThisMonth.fromJson(Map<String, dynamic> json) {
    return MessagesThisMonth(
      month: json['month'] as String? ?? '',
      total: MessageCounts.fromJson(json['total'] as Map<String, dynamic>),
      channels: (json['channels'] as List<dynamic>? ?? const [])
          .map((line) => MessageCounts.fromJson(line as Map<String, dynamic>))
          .toList(),
      feeRelated: json['fee_related'] as int? ?? 0,
      providerDelivers: json['provider_delivers'] as bool? ?? false,
    );
  }

  /// "July 2026".
  final String month;
  final MessageCounts total;
  final List<MessageCounts> channels;

  /// Fee reminders and other fee messages among them.
  final int feeRelated;

  /// False while the school's SMS goes through a gateway that delivers
  /// nothing - said on screen, so "sent" is not taken at its word.
  final bool providerDelivers;
}

/// The log's own statuses. There is no "delivered": no provider reports
/// delivery back yet, and "sent" is only the provider accepting a message.
class MessageCounts {
  const MessageCounts({
    required this.channel,
    required this.label,
    required this.sent,
    required this.queued,
    required this.failed,
    required this.skipped,
  });

  factory MessageCounts.fromJson(Map<String, dynamic> json) {
    return MessageCounts(
      channel: json['channel'] as String? ?? '',
      label: json['label'] as String? ?? '',
      sent: json['sent'] as int? ?? 0,
      queued: json['queued'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
      skipped: json['skipped'] as int? ?? 0,
    );
  }

  final String channel;
  final String label;
  final int sent;
  final int queued;
  final int failed;
  final int skipped;

  int get all => sent + queued + failed + skipped;
}
