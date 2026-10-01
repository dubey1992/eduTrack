/// Every word on the public homepage, in one place (docs/marketing-content.md).
///
/// **These are the defaults, and they live here rather than on the server
/// on purpose.** The homepage is served to anybody who types the address,
/// including when the backend is down, the table is empty, or the request
/// has not come back yet. A marketing page that goes blank because an API
/// call did would be worse than one nobody can edit - so the page always
/// has its own copy, and the server sends only what somebody changed.
///
/// A key is `section.field`. Nothing enforces that shape yet; the Super
/// Admin editor arrives in the next slice and brings the declaration that
/// does (docs/marketing-content.md, slice 2).
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
};
