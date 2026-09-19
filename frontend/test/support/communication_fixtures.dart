import 'package:edutrack_app/features/communication/data/models/message.dart';

/// The prototype's own log rows, as models.
const absenceSms = Message(
  id: 1,
  schoolId: 1,
  event: 'attendance.absent',
  eventLabel: 'Marked absent',
  category: MessageCategory.attendance,
  channel: MessageChannel.sms,
  recipientName: 'Raj Kumar',
  recipientMobile: '+91 9876543210',
  studentId: 7,
  studentName: 'Arjun Kumar',
  subject: null,
  body: 'Arjun Kumar was marked ABSENT on 16 Sep 2026.',
  status: MessageStatus.sent,
  provider: 'log',
  providerLabel: 'Demo Gateway',
  failureReason: null,
  sentAt: '2026-09-16T08:42:00.000000Z',
  readAt: null,
  createdAt: '2026-09-16T08:42:00.000000Z',
  createdAtLabel: '8:42 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

const boardingSms = Message(
  id: 2,
  schoolId: 1,
  event: 'transport.boarded',
  eventLabel: 'Boarded the bus',
  category: MessageCategory.transport,
  channel: MessageChannel.sms,
  recipientName: 'Neha Mehta',
  recipientMobile: '+91 9812345678',
  studentId: 8,
  studentName: 'Aarav Mehta',
  subject: null,
  body: 'Aarav Mehta boarded Bus 04 at Lake View at 7:42 AM.',
  status: MessageStatus.sent,
  provider: 'log',
  providerLabel: 'Demo Gateway',
  failureReason: null,
  sentAt: '2026-09-16T07:42:00.000000Z',
  readAt: null,
  createdAt: '2026-09-16T07:42:00.000000Z',
  createdAtLabel: '7:42 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

/// One the gateway rejected, so the log offers to send it again.
const failedSms = Message(
  id: 3,
  schoolId: 1,
  event: 'attendance.absent',
  eventLabel: 'Marked absent',
  category: MessageCategory.attendance,
  channel: MessageChannel.sms,
  recipientName: 'Rohit Singh',
  recipientMobile: '+91 9800000000',
  studentId: 9,
  studentName: 'Meera Singh',
  subject: null,
  body: 'Meera Singh was marked ABSENT on 16 Sep 2026.',
  status: MessageStatus.failed,
  provider: 'log',
  providerLabel: 'Demo Gateway',
  failureReason: 'The gateway rejected the number.',
  sentAt: null,
  readAt: null,
  createdAt: '2026-09-16T08:45:00.000000Z',
  createdAtLabel: '8:45 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

/// One the school wanted to send but had no number for.
const skippedSms = Message(
  id: 4,
  schoolId: 1,
  event: 'attendance.absent',
  eventLabel: 'Marked absent',
  category: MessageCategory.attendance,
  channel: MessageChannel.sms,
  recipientName: 'Anita Rao',
  recipientMobile: null,
  studentId: 10,
  studentName: 'Kiran Rao',
  subject: null,
  body: 'Kiran Rao was marked ABSENT on 16 Sep 2026.',
  status: MessageStatus.skipped,
  provider: 'log',
  providerLabel: 'Demo Gateway',
  failureReason: 'No mobile number on record.',
  sentAt: null,
  readAt: null,
  createdAt: '2026-09-16T08:46:00.000000Z',
  createdAtLabel: '8:46 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

const leaveInApp = Message(
  id: 5,
  schoolId: 1,
  event: 'leave.approved',
  eventLabel: 'Leave approved',
  category: MessageCategory.leave,
  channel: MessageChannel.inApp,
  recipientName: 'Priya Sharma',
  recipientMobile: null,
  studentId: null,
  studentName: null,
  subject: null,
  body: 'Your casual leave from 21 Sep 2026 to 22 Sep 2026 has been approved.',
  status: MessageStatus.sent,
  provider: null,
  providerLabel: null,
  failureReason: null,
  sentAt: '2026-09-16T09:00:00.000000Z',
  readAt: null,
  createdAt: '2026-09-16T09:00:00.000000Z',
  createdAtLabel: '9:00 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

const readInApp = Message(
  id: 6,
  schoolId: 1,
  event: 'leave.rejected',
  eventLabel: 'Leave rejected',
  category: MessageCategory.leave,
  channel: MessageChannel.inApp,
  recipientName: 'Priya Sharma',
  recipientMobile: null,
  studentId: null,
  studentName: null,
  subject: null,
  body: 'Your medical leave from 01 Sep 2026 to 02 Sep 2026 was not approved.',
  status: MessageStatus.sent,
  provider: null,
  providerLabel: null,
  failureReason: null,
  sentAt: '2026-09-15T09:00:00.000000Z',
  readAt: '2026-09-15T10:00:00.000000Z',
  createdAt: '2026-09-15T09:00:00.000000Z',
  createdAtLabel: '9:00 AM',
  sentAtLabel: null,
  createdOnLabel: '15 Sep 2026',
);

/// An announcement's in-app copy, which carries its title as the subject.
const announcementInApp = Message(
  id: 7,
  schoolId: 1,
  event: 'announcement.published',
  eventLabel: 'Announcement',
  category: MessageCategory.announcement,
  channel: MessageChannel.inApp,
  recipientName: 'Priya Sharma',
  recipientMobile: null,
  studentId: null,
  studentName: null,
  subject: 'Sports day moved',
  body: 'Sunrise Public School: Sports day moved - The sports day is now on Friday.',
  status: MessageStatus.sent,
  provider: null,
  providerLabel: null,
  failureReason: null,
  sentAt: '2026-09-16T09:30:00.000000Z',
  readAt: null,
  createdAt: '2026-09-16T09:30:00.000000Z',
  createdAtLabel: '9:30 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

/// A fee reminder's email copy - the log shows where it went.
const feeEmail = Message(
  id: 8,
  schoolId: 1,
  event: 'fee.reminder',
  eventLabel: 'Fee reminder',
  category: MessageCategory.fee,
  channel: MessageChannel.email,
  recipientName: 'Raj Kumar',
  recipientMobile: '+91 9876543210',
  recipientEmail: 'raj.kumar@example.com',
  studentId: 7,
  studentName: 'Arjun Kumar',
  subject: 'Fee reminder',
  body: 'A fee of INR 1,500.00 for Arjun Kumar is due on 30 Sep 2026.',
  status: MessageStatus.sent,
  provider: 'smtp',
  providerLabel: 'Email',
  failureReason: null,
  sentAt: '2026-09-16T10:00:00.000000Z',
  readAt: null,
  createdAt: '2026-09-16T10:00:00.000000Z',
  createdAtLabel: '10:00 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

/// A WhatsApp copy of a message written by hand.
const noticeWhatsapp = Message(
  id: 9,
  schoolId: 1,
  event: 'general.message',
  eventLabel: 'Message',
  category: MessageCategory.general,
  channel: MessageChannel.whatsapp,
  recipientName: 'Neha Mehta',
  recipientMobile: '+91 9812345678',
  studentId: 8,
  studentName: 'Aarav Mehta',
  subject: 'PTA meeting',
  body: 'Sunrise Public School: PTA meeting - The PTA meets on Friday at 3 PM.',
  status: MessageStatus.queued,
  provider: 'meta',
  providerLabel: 'Meta WhatsApp Cloud API',
  failureReason: null,
  sentAt: null,
  readAt: null,
  createdAt: '2026-09-16T10:05:00.000000Z',
  createdAtLabel: '10:05 AM',
  sentAtLabel: null,
  createdOnLabel: '16 Sep 2026',
);

const absentTemplate = MessageTemplate(
  event: 'attendance.absent',
  eventLabel: 'Marked absent',
  category: MessageCategory.attendance,
  channels: [MessageChannel.sms, MessageChannel.whatsapp, MessageChannel.email],
  body: '{student_name} was marked ABSENT on {date}.',
  defaultBody: '{student_name} was marked ABSENT on {date}.',
  isCustom: false,
  tokens: ['student_name', 'class_name', 'date', 'school_name', 'guardian_name'],
  updatedByName: null,
);

const boardedTemplate = MessageTemplate(
  event: 'transport.boarded',
  eventLabel: 'Boarded the bus',
  category: MessageCategory.transport,
  channels: [MessageChannel.sms, MessageChannel.whatsapp, MessageChannel.email],
  body: 'Reworded: {student_name} is on {vehicle_name}.',
  defaultBody: '{student_name} boarded {vehicle_name} at {stop_name} at {time}.',
  isCustom: true,
  tokens: ['student_name', 'stop_name', 'vehicle_name', 'route_name', 'time', 'date', 'school_name', 'guardian_name'],
  updatedByName: 'Anita Sharma',
);

/// The one written by hand, already mapped to an approved WhatsApp template.
const generalMessageTemplate = MessageTemplate(
  event: 'general.message',
  eventLabel: 'Message',
  category: MessageCategory.general,
  channels: [MessageChannel.sms, MessageChannel.inApp, MessageChannel.whatsapp, MessageChannel.email],
  body: '{school_name}: {subject} - {body}',
  defaultBody: '{school_name}: {subject} - {body}',
  isCustom: false,
  tokens: ['school_name', 'subject', 'body', 'recipient_name'],
  updatedByName: null,
  isManual: true,
  whatsapp: WhatsAppTemplateMapping(
    templateName: 'school_notice',
    language: 'en',
    parameters: ['subject', 'body'],
    updatedAt: '2026-09-16T09:00:00.000000Z',
  ),
);

const defaultTemplates = [absentTemplate, boardedTemplate, generalMessageTemplate];

const defaultSettings = CommunicationSettings(
  schoolId: 1,
  smsEnabled: true,
  attendanceAlerts: AttendanceAlertMode.absentOnly,
  transportAlertsEnabled: true,
  leaveAlertsEnabled: true,
  provider: 'log',
  providerLabel: 'Demo Gateway',
  providerDelivers: false,
  senderId: null,
  availableProviders: [
    SmsProviderOption(value: 'log', label: 'Demo Gateway'),
    twilioOption,
  ],
  availableWhatsappProviders: [
    SmsProviderOption(value: 'log', label: 'Demo Gateway'),
    twilioOption,
    metaOption,
  ],
  credentialFields: credentialFields,
  isSaved: false,
);

const twilioOption = SmsProviderOption(value: 'twilio', label: 'Twilio');
const metaOption = SmsProviderOption(value: 'meta', label: 'Meta WhatsApp Cloud API');

/// What each real provider asks for, as the server lists it.
const credentialFields = {
  'twilio': [
    CredentialField(key: 'account_sid', label: 'Account SID', secret: false),
    CredentialField(key: 'auth_token', label: 'Auth token', secret: true),
    CredentialField(key: 'sms_from', label: 'SMS sender number', secret: false),
    CredentialField(key: 'whatsapp_from', label: 'WhatsApp sender number', secret: false),
  ],
  'meta': [
    CredentialField(key: 'phone_number_id', label: 'Phone number ID', secret: false),
    CredentialField(key: 'access_token', label: 'Access token', secret: true),
  ],
};

/// A school on Twilio for SMS and Meta for WhatsApp, with a Twilio account
/// partly on file: the SID and token are saved, the sender numbers are not.
const twilioSettings = CommunicationSettings(
  schoolId: 1,
  smsEnabled: true,
  attendanceAlerts: AttendanceAlertMode.absentOnly,
  transportAlertsEnabled: true,
  leaveAlertsEnabled: true,
  provider: 'twilio',
  providerLabel: 'Twilio',
  providerDelivers: true,
  senderId: null,
  availableProviders: [
    SmsProviderOption(value: 'log', label: 'Demo Gateway'),
    twilioOption,
  ],
  isSaved: true,
  whatsappEnabled: true,
  whatsappProvider: 'meta',
  whatsappProviderLabel: 'Meta WhatsApp Cloud API',
  whatsappProviderDelivers: true,
  availableWhatsappProviders: [
    SmsProviderOption(value: 'log', label: 'Demo Gateway'),
    twilioOption,
    metaOption,
  ],
  emailEnabled: true,
  emailDelivers: false,
  credentialFields: credentialFields,
  credentials: {
    'twilio': {
      'account_sid': CredentialStatus(isSet: true, hint: '…5678'),
      'auth_token': CredentialStatus(isSet: true),
      'sms_from': CredentialStatus(isSet: false),
      'whatsapp_from': CredentialStatus(isSet: false),
    },
    'meta': {'phone_number_id': CredentialStatus(isSet: false), 'access_token': CredentialStatus(isSet: false)},
  },
);

/// Copies a message with a couple of fields changed - the model is
/// deliberately immutable, and only the fakes need this.
Message messageAs(Message source, {MessageStatus? status, Object? failureReason = _keep, String? readAt}) {
  return Message(
    id: source.id,
    schoolId: source.schoolId,
    event: source.event,
    eventLabel: source.eventLabel,
    category: source.category,
    channel: source.channel,
    recipientName: source.recipientName,
    recipientMobile: source.recipientMobile,
    recipientEmail: source.recipientEmail,
    studentId: source.studentId,
    studentName: source.studentName,
    subject: source.subject,
    body: source.body,
    status: status ?? source.status,
    provider: source.provider,
    providerLabel: source.providerLabel,
    failureReason: failureReason == _keep ? source.failureReason : failureReason as String?,
    sentAt: source.sentAt,
    readAt: readAt ?? source.readAt,
    createdAt: source.createdAt,
    createdAtLabel: source.createdAtLabel,
    createdOnLabel: source.createdOnLabel,
    sentAtLabel: source.sentAtLabel,
  );
}

MessageTemplate templateAs(MessageTemplate source, {String? body, bool? isCustom, Object? whatsapp = _keep}) {
  return MessageTemplate(
    event: source.event,
    eventLabel: source.eventLabel,
    category: source.category,
    channels: source.channels,
    body: body ?? source.body,
    defaultBody: source.defaultBody,
    isCustom: isCustom ?? source.isCustom,
    tokens: source.tokens,
    updatedByName: source.updatedByName,
    isManual: source.isManual,
    whatsapp: whatsapp == _keep ? source.whatsapp : whatsapp as WhatsAppTemplateMapping?,
  );
}

const _keep = Object();
