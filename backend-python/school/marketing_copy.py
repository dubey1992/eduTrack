"""The homepage's own words, for the plain-HTML website (docs/seo.md, S2).

The same copy as the app's `marketing_defaults.dart`: what the page says
wherever the Super Admin has not changed it. The app keeps its own copy so
its homepage renders with no backend at all; the server needs one too,
because it now writes the public pages itself. A test reads the Dart file
and refuses to let the two drift, so change both together.

`words()` merges a published document over these the way the app's
`MarketingContent` does: a blank override, or an empty list, means the
default.
"""

from __future__ import annotations

TEXT: dict[str, str] = {'nav.wordmark': 'School365ai',
 'nav.tagline': 'Smarter Schools. Brighter Futures.',
 'nav.login': 'Login',
 'nav.join': 'Join Early Access',
 'nav.joinShort': 'Join',
 'nav.demo': 'Request a Demo',
 'hero.eyebrow': 'A Complete School Management Platform',
 'hero.headline': 'Run Your School Smarter, Together.',
 'hero.body': 'Students, Teachers, Academics, Attendance, Transport, Communication, Payroll and more — all '
              'in one simple and powerful platform.',
 'hero.primaryButton': 'Join Early Access →',
 'hero.demoButton': 'Request a Demo',
 'hero.secondaryButton': 'Watch Video',
 'hero.trustLine': 'Trusted by forward-thinking school leaders worldwide.',
 'features.eyebrow': 'EVERYTHING YOUR SCHOOL NEEDS',
 'features.title': 'Powerful Features for Modern Schools',
 'features.body': 'A complete solution to simplify school operations and enhance learning experiences.',
 'mobile.eyebrow': 'MOBILE APP',
 'mobile.headline': 'Your School in\nYour Pocket',
 'mobile.body': 'Stay connected on the go with mobile apps for parents, teachers, students, and staff.',
 'web.eyebrow': 'WEB APPLICATION',
 'web.headline': 'Complete Control\non the Web',
 'web.body': 'Powerful admin dashboard for school leaders and staff.',
 'cta.headline': 'Be Part of the Future of Education',
 'cta.body': "We're currently inviting schools worldwide to join our early access program.\n"
             'Get exclusive access, provide feedback, and help shape the future of School365ai.',
 'cta.button': 'Join Early Access →',
 'cta.demoButton': 'Request a Demo',
 'footer.wordmark': 'School365ai',
 'footer.blurb': 'Modern school management for smarter schools and brighter futures.',
 'footer.newsletterTitle': 'Stay Updated',
 'footer.newsletterBody': 'Get the latest news and updates.',
 'footer.copyright': '© 2026 School365ai. All rights reserved.',
 'footer.tagline': 'Smarter Schools. Brighter Futures.',
 'footer.productTitle': 'Product',
 'footer.companyTitle': 'Company',
 'footer.resourceTitle': 'Resources',
 'web.button': 'Explore Web Dashboard →'}

LISTS: dict[str, list[dict[str, str]]] = {'hero.stats': [{'source': 'typed', 'value': '500+', 'label': 'Schools (Target)'},
                {'source': 'typed', 'value': 'Global', 'label': 'Reach'},
                {'source': 'typed', 'value': '1M+', 'label': 'Students (Target)'},
                {'source': 'typed', 'value': 'Secure', 'label': '& Reliable'},
                {'source': 'typed', 'value': 'Better', 'label': 'Tomorrow'}],
 'features.items': [{'icon': '☺',
                     'title': 'Student Management',
                     'body': 'Complete student records and academic details'},
                    {'icon': '☺',
                     'title': 'Teacher Management',
                     'body': 'Staff records, workload and performance'},
                    {'icon': '✓', 'title': 'Attendance', 'body': 'Real-time attendance with notifications'},
                    {'icon': '¤', 'title': 'Academics', 'body': 'Timetable, exams and report cards'},
                    {'icon': '⌣', 'title': 'Fees & Payments', 'body': 'Online and offline fee management'},
                    {'icon': '🚌',
                     'title': 'Transport Management',
                     'body': 'Live tracking and route management'},
                    {'icon': '✉',
                     'title': 'Communication',
                     'body': 'Connect with parents, teachers and students'},
                    {'icon': '⚭', 'title': 'HR & Payroll', 'body': 'Leave, salary and staff management'},
                    {'icon': '▥',
                     'title': 'Reports & Analytics',
                     'body': 'Insights for better decision making'},
                    {'icon': '☰', 'title': 'Administration', 'body': 'Manage your school effortlessly'}],
 'web.bullets': [{'text': 'All features in one place'},
                 {'text': 'Real-time insights'},
                 {'text': 'Secure and scalable'},
                 {'text': 'Access from anywhere'}],
 'footer.productLinks': [{'label': 'Features', 'url': 'https://school365ai.com/features'},
                         {'label': 'Web Dashboard', 'url': '/login'},
                         {'label': 'Mobile App', 'url': 'https://school365ai.com/mobile-app'},
                         {'label': 'Pricing', 'url': 'https://school365ai.com/pricing'}],
 'footer.companyLinks': [{'label': 'About Us', 'url': '/about'},
                         {'label': 'Careers', 'url': 'https://school365ai.com/careers'},
                         {'label': 'Blog', 'url': 'https://school365ai.com/blog'},
                         {'label': 'Contact', 'url': 'https://school365ai.com/contact'}],
 'footer.resourceLinks': [{'label': 'Help Center', 'url': 'https://school365ai.com/help'},
                          {'label': 'Privacy Policy', 'url': '/privacy'},
                          {'label': 'Terms', 'url': '/terms'},
                          {'label': 'Security', 'url': 'https://school365ai.com/security'}]}


class Words:
    """One published document read over the defaults."""

    def __init__(self, document: dict):
        self.document = document or {}

    def text(self, key: str) -> str:
        value = self.document.get(key)

        if isinstance(value, str) and value.strip():
            return value

        return TEXT.get(key, "")

    def list(self, key: str) -> list[dict[str, str]]:
        value = self.document.get(key)

        if isinstance(value, list) and value and all(isinstance(item, dict) for item in value):
            return value

        return LISTS.get(key, [])
