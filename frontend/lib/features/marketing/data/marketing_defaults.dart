/// Every word on the public homepage, in one place (docs/marketing-content.md).
///
/// **These are the defaults, and they live here rather than on the server
/// on purpose.** The homepage is served to anybody who types the address,
/// including when the backend is down, the table is empty, or the request
/// has not come back yet. A marketing page that goes blank because an API
/// call did would be worse than one nobody can edit - so the page always
/// has its own copy, and the server sends only what somebody changed.
///
/// A key is `section.field`, matching the declaration in
/// `school/marketing.py` that the editor's form is drawn from. A test on
/// each side refuses to let the two drift.
library;

const marketingDefaults = <String, String>{
  // -- the bar across the top --------------------------------------------
  'nav.wordmark': 'School365ai',
  'nav.tagline': 'Smarter Schools. Brighter Futures.',
  'nav.login': 'Login',
  'nav.join': 'Join Early Access',
  'nav.joinShort': 'Join',

  // -- the first thing anybody reads -------------------------------------
  'hero.eyebrow': 'A Complete School Management Platform',
  'hero.headline': 'Run Your School Smarter, Together.',
  'hero.body':
      'Students, Teachers, Academics, Attendance, Transport, Communication, '
      'Payroll and more — all in one simple and powerful platform.',
  'hero.primaryButton': 'Join Early Access →',
  'hero.secondaryButton': 'Watch Video',
  'hero.trustLine': 'Trusted by forward-thinking school leaders worldwide.',

  // -- what the product does ---------------------------------------------
  'features.eyebrow': 'EVERYTHING YOUR SCHOOL NEEDS',
  'features.title': 'Powerful Features for Modern Schools',
  'features.body': 'A complete solution to simplify school operations and enhance learning experiences.',

  // -- the phone ----------------------------------------------------------
  'mobile.eyebrow': 'MOBILE APP',
  'mobile.headline': 'Your School in\nYour Pocket',
  'mobile.body': 'Stay connected on the go with mobile apps for parents, teachers, students, and staff.',

  // -- the browser --------------------------------------------------------
  'web.eyebrow': 'WEB APPLICATION',
  'web.headline': 'Complete Control\non the Web',
  'web.body': 'Powerful admin dashboard for school leaders and staff.',

  // -- the ask ------------------------------------------------------------
  'cta.headline': 'Be Part of the Future of Education',
  'cta.body':
      "We're currently inviting schools worldwide to join our early access program.\n"
      'Get exclusive access, provide feedback, and help shape the future of School365ai.',
  'cta.button': 'Join Early Access →',

  // -- the bottom ---------------------------------------------------------
  'footer.wordmark': 'School365ai',
  'footer.blurb': 'Modern school management for smarter schools and brighter futures.',
  'footer.newsletterTitle': 'Stay Updated',
  'footer.newsletterBody': 'Get the latest news and updates.',
  'footer.copyright': '© 2026 School365ai. All rights reserved.',
  'footer.tagline': 'Smarter Schools. Brighter Futures.',
  'footer.productTitle': 'Product',
  'footer.companyTitle': 'Company',
  'footer.resourceTitle': 'Resources',
  'web.button': 'Explore Web Dashboard →',
};

/// The repeating parts of the page - the feature cards, the figures under
/// the hero, the ticked list and the footer's three columns.
///
/// Here for the same reason as the words above: a list absent from the
/// server's document is this one, so the page draws its full self before
/// any request comes back, and still does if none ever does.
///
/// Each item's keys match the item fields the declaration names, so an
/// item read back from the server and one from here are the same shape.
const marketingListDefaults = <String, List<Map<String, String>>>{
  'hero.stats': [
    {'source': 'typed', 'value': '500+', 'label': 'Schools (Target)'},
    {'source': 'typed', 'value': 'Global', 'label': 'Reach'},
    {'source': 'typed', 'value': '1M+', 'label': 'Students (Target)'},
    {'source': 'typed', 'value': 'Secure', 'label': '& Reliable'},
    {'source': 'typed', 'value': 'Better', 'label': 'Tomorrow'},
  ],
  'features.items': [
    {'icon': '☺', 'title': 'Student Management', 'body': 'Complete student records and academic details'},
    {'icon': '☺', 'title': 'Teacher Management', 'body': 'Staff records, workload and performance'},
    {'icon': '✓', 'title': 'Attendance', 'body': 'Real-time attendance with notifications'},
    {'icon': '¤', 'title': 'Academics', 'body': 'Timetable, exams and report cards'},
    {'icon': '⌣', 'title': 'Fees & Payments', 'body': 'Online and offline fee management'},
    {'icon': '🚌', 'title': 'Transport Management', 'body': 'Live tracking and route management'},
    {'icon': '✉', 'title': 'Communication', 'body': 'Connect with parents, teachers and students'},
    {'icon': '⚭', 'title': 'HR & Payroll', 'body': 'Leave, salary and staff management'},
    {'icon': '▥', 'title': 'Reports & Analytics', 'body': 'Insights for better decision making'},
    {'icon': '☰', 'title': 'Administration', 'body': 'Manage your school effortlessly'},
  ],
  'web.bullets': [
    {'text': 'All features in one place'},
    {'text': 'Real-time insights'},
    {'text': 'Secure and scalable'},
    {'text': 'Access from anywhere'},
  ],
  'footer.productLinks': [
    {'label': 'Features'},
    {'label': 'Web Dashboard'},
    {'label': 'Mobile App'},
    {'label': 'Pricing'},
  ],
  'footer.companyLinks': [
    {'label': 'About Us'},
    {'label': 'Careers'},
    {'label': 'Blog'},
    {'label': 'Contact'},
  ],
  'footer.resourceLinks': [
    {'label': 'Help Center'},
    {'label': 'Privacy Policy'},
    {'label': 'Terms'},
    {'label': 'Security'},
  ],
};
