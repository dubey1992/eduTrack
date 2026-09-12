import 'package:edutrack_app/features/announcements/data/models/announcement.dart';

/// The prototype's own example notice.
const parentMeeting = Announcement(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  title: 'Parent meeting',
  body: 'Parent meeting scheduled Friday at 3 PM.',
  audienceType: AnnouncementAudience.parents,
  audienceId: null,
  audienceLabel: 'Parents',
  channels: AnnouncementChannels.smsAndInApp,
  expiresAt: null,
  hasExpired: false,
  publishedByName: 'Anita Sharma',
  publishedAt: '2026-09-16T07:30:00.000000Z',
  recipientsCount: 42,
  smsCount: 42,
  inAppCount: 0,
);

const syllabusReview = Announcement(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  title: 'Syllabus review',
  body: 'Maths teachers, please submit your syllabus progress by Thursday.',
  audienceType: AnnouncementAudience.department,
  audienceId: 3,
  audienceLabel: 'Mathematics',
  channels: AnnouncementChannels.inAppOnly,
  expiresAt: null,
  hasExpired: false,
  publishedByName: 'Vikram Rao',
  publishedAt: '2026-09-15T10:00:00.000000Z',
  recipientsCount: 6,
  smsCount: 0,
  inAppCount: 6,
);

/// One whose expiry has passed, so it has dropped out of the feed.
const oldSportsDay = Announcement(
  id: 3,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  title: 'Sports day',
  body: 'Sports day is on the 10th.',
  audienceType: AnnouncementAudience.allSchool,
  audienceId: null,
  audienceLabel: 'All School',
  channels: AnnouncementChannels.smsOnly,
  expiresAt: '2026-09-11',
  hasExpired: true,
  publishedByName: 'Anita Sharma',
  publishedAt: '2026-09-05T09:00:00.000000Z',
  recipientsCount: 120,
  smsCount: 120,
  inAppCount: 0,
);
