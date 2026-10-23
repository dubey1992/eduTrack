import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The privacy policy, which Google Play requires of any app that handles
/// location and which the footer has been promising since the site went up
/// (docs/driver-app.md, D6.1).
///
/// Public on purpose: it has to be readable by somebody who has not
/// installed the app and never will - a parent, a reviewer, a school's
/// lawyer. So it lives outside the signed-in shell, like the homepage.
///
/// Everything here is drawn from what the code actually does. Where a fact
/// is the operator's rather than the software's - who the company is, which
/// country's law applies - it says so plainly instead of inventing one.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// Changed whenever the substance changes, not whenever a word does.
  static const lastUpdated = 'October 23, 2026';

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Privacy Policy', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('Last updated $lastUpdated', style: TextStyle(color: muted)),
              const SizedBox(height: 24),
              const _Paragraph(
                'School365ai is school management software. Schools use it to run their own records: '
                'students, staff, attendance, timetables and school transport. The School365ai Driver '
                'app is the part of it carried on a school bus.',
              ),
              const _Paragraph(
                'The school is the owner of the information in its account. We hold and process that '
                'information on the school\'s behalf and under its instructions. If you are a parent or '
                'a member of staff asking what is held about you, your school is the place to ask, and '
                'they can answer from their own screens.',
              ),

              const _Heading('What the Driver app collects'),
              const _Bullet(
                'Where the bus is.',
                'While a trip is running and the driver or attendant has location sharing switched on, '
                    'the app sends the phone\'s position to the school. This is how the office and the '
                    'school\'s live map show where a bus is on its route.',
              ),
              const _Bullet(
                'Only during a trip.',
                'Sharing starts when a trip starts and stops when it ends, when the crew switches it '
                    'off, or when they leave the trip screen. The app does not ask for background location '
                    'permission and cannot follow a phone when no trip is running. A notification is shown '
                    'the whole time a trip is sharing its position, so it is never happening quietly.',
              ),
              const _Bullet(
                'What the crew marks.',
                'Which child boarded, was dropped off or was absent, at which stop, at what time, and '
                    'which crew member marked it.',
              ),
              const _Bullet(
                'That a parent was called.',
                'When the crew uses Call parent, the app records that a call was made, about which '
                    'child, and when. The phone number itself is never recorded, and the crew is never '
                    'shown it.',
              ),
              const _Bullet(
                'The account.',
                'Name, mobile number, and the phone the account was set up on, so a passcode cannot be '
                    'used from anywhere else.',
              ),

              const _Heading('How long it is kept'),
              const _Paragraph(
                'Bus positions are deleted after 30 days. They exist so a school can see where a bus '
                'is now and answer a question about this morning, not to build a history of anybody\'s '
                'movements.',
              ),
              const _Paragraph(
                'Trip records - who boarded where, and when - are part of the school\'s own records and '
                'are kept for as long as the school keeps them. Account records are kept while the '
                'account exists.',
              ),

              const _Heading('Who can see it'),
              const _Paragraph(
                'Staff at your own school, and only at your own school. Every screen and every request '
                'is checked against the school the signed-in account belongs to, and against what that '
                'person\'s role allows: a bus crew member reaches the routes they run and nothing else.',
              ),
              const _Paragraph(
                'We do not sell information, and we do not use it for advertising. The app carries no '
                'advertising, no analytics and no tracking software.',
              ),

              const _Heading('Services we rely on'),
              const _Bullet(
                'Google Maps.',
                'The school\'s web portal draws maps using Google Maps. Google receives the map requests '
                    'it needs to draw them.',
              ),
              const _Bullet(
                'Google Fonts.',
                'The apps load their typeface from Google\'s font service, which sees the request and '
                    'the device\'s IP address, as any web request does.',
              ),
              const _Bullet(
                'Messaging and email providers.',
                'Where a school switches on SMS, WhatsApp or email alerts, the message and the '
                    'recipient\'s number or address are handed to the provider the school has configured, '
                    'so that it can be delivered.',
              ),
              const _Bullet(
                'Hosting.',
                'The service and its database run on the hosting the school\'s operator has arranged.',
              ),

              const _Heading('Children'),
              const _Paragraph(
                'The app holds information about children because that is what a school bus run is. '
                'Children do not have accounts and do not use this app. Information about a child is '
                'entered by their school and is visible to that school\'s staff.',
              ),

              const _Heading('Keeping it safe'),
              const _Paragraph(
                'Access needs an account, and on the bus it needs the registered phone as well as a '
                'passcode. Repeated wrong passcodes lock the account until the school unlocks it. '
                'Passwords and passcodes are stored only as one-way hashes - nobody, including us, can '
                'read them back. Every change to a record is logged with who made it and when.',
              ),

              const _Heading('Your choices'),
              const _Paragraph(
                'A crew member can switch location sharing off at any time from the trip screen. The '
                'trip, and marking children on and off, keeps working; the school simply will not see '
                'where the bus is.',
              ),
              const _Paragraph(
                'To see, correct or delete what is held about you, ask your school. If your school '
                'needs our help to do it, they can ask us.',
              ),

              const _Heading('Who to contact'),
              const _Operator(),

              const _Heading('Changes'),
              const _Paragraph('If this policy changes in substance, the date at the top changes with it.'),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one section the software cannot fill in for itself.
///
/// Who the operating company is, where it is, and which country's law
/// applies are facts about the business, not about the code. Rather than
/// invent them - which would be worse than leaving them out - the page says
/// what belongs here.
class _Operator extends StatelessWidget {
  const _Operator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.appColors.infoContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(
        'School365ai is operated by the company named in your school\'s agreement, which is also where '
        'the address for written notices is given. Questions about this policy, or about information '
        'held about you, should go to your school in the first instance; they can reach us on your '
        'behalf.',
        style: TextStyle(color: context.appColors.onInfoContainer),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: const TextStyle(height: 1.5)),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 6, right: 10), child: Icon(Icons.circle, size: 7)),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: body),
                ],
              ),
              style: const TextStyle(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
