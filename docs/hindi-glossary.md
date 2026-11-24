# Hindi glossary for the phone apps (M11)

The words the Bus, Staff and Family apps use in Hindi
(docs/mobile-apps-review.md, M11, decided 2026-11-24). One word for one
thing, across all three apps. Written for people who use the apps every
day: plain, spoken Hindi; an English word kept where it is what people say
(बस, रिपोर्ट, ऐप, पासकोड).

**Status: drafted, awaiting review by a native speaker before release.**

## Style

- Address the person as **आप**; buttons are short imperatives: सेव करें,
  भेजें, रद्द करें, फिर से कोशिश करें.
- Numbers, times and dates stay as they are (7:42 AM, 11/30/2026) - the
  same US order as the rest of the product.
- Names of people, schools, classes, subjects, stops and routes are data and
  are never translated.
- Keep sentences short; a phone screen is narrow and Devanagari runs long.

## Terms

| English | Hindi |
|---|---|
| App | ऐप |
| Sign in / Sign out | साइन इन करें / साइन आउट करें |
| Passcode | पासकोड |
| Set-up code | सेटअप कोड |
| Profile | प्रोफ़ाइल |
| Settings | सेटिंग्स |
| Today | आज |
| Home | होम |
| School | स्कूल |
| Class / Section | कक्षा / सेक्शन |
| Student / child | छात्र / बच्चा |
| Parent / guardian | अभिभावक |
| Teacher | शिक्षक |
| Register (attendance) | हाज़िरी रजिस्टर |
| Take the register | हाज़िरी लें |
| Present / Absent / Late / On leave | उपस्थित / अनुपस्थित / देर से / छुट्टी पर |
| Not marked yet | अभी दर्ज नहीं |
| Period | पीरियड |
| Teaching report | शिक्षण रिपोर्ट |
| Homework | होमवर्क |
| Syllabus | पाठ्यक्रम |
| Test / Marks / Results | टेस्ट / अंक / परिणाम |
| Report card | रिपोर्ट कार्ड |
| Leave (time off) | छुट्टी |
| Pay / payslip | वेतन / वेतन पर्ची |
| Fees / Receipt / Due / Overdue | फ़ीस / रसीद / देय / बकाया |
| Notice | सूचना |
| Messages / Inbox | संदेश / इनबॉक्स |
| Bus / Trip / Route / Stop | बस / ट्रिप / रूट / स्टॉप |
| Pickup / Drop | पिकअप / ड्रॉप |
| Boarded / Dropped | बस में बैठा / उतरा |
| Reached | पहुँच गए |
| Running late | देर हो रही है |
| Driver / Attendant (bus crew) | ड्राइवर / अटेंडेंट (बस स्टाफ़) |
| Location / share location | लोकेशन / लोकेशन शेयर करें |
| Check in / Check out (staff) | चेक इन / चेक आउट |
| Photo | फ़ोटो |
| File / Attach | फ़ाइल / अटैच करें |
| Save / Send / Submit | सेव करें / भेजें / जमा करें |
| Cancel / Close / Back | रद्द करें / बंद करें / वापस |
| Retry | फिर से कोशिश करें |
| Loading | लोड हो रहा है |
| No connection | इंटरनेट नहीं है |
| Saved on the phone, not sent | फ़ोन में सेव है, अभी भेजा नहीं गया |
| App lock | ऐप लॉक |
| Language | भाषा |
| Holiday (school closed) | अवकाश (not छुट्टी, which is leave) |
| Pending | बाकी / लंबित (a request awaiting a decision) |
| Approve / Reject | मंज़ूर करें / नामंज़ूर करें |
| Withdraw / Undo | वापस लें |
| Review | समीक्षा |
| Department | विभाग |
| Casual / Medical / Earned leave | आकस्मिक / चिकित्सा / अर्जित छुट्टी |
| Instalment | किस्त |
| Paid / Part paid | भुगतान हो गया / कुछ भुगतान हुआ |
| Discount / Waived | छूट / माफ़ |
| Credit | क्रेडिट |
| Refund | वापसी |
| Late fine | विलंब शुल्क |
| Cash / Cheque | नकद / चेक |
| Statement (fees) | फ़ीस विवरण |
| Earnings / Deductions / Net pay | कमाई / कटौती / कुल मिलने वाला वेतन |
| Working days | कार्य दिवस |
| Publish / Draft / Template | प्रकाशित करें / ड्राफ़्ट / टेम्पलेट |
| Announcement | घोषणा |
| Emergency | आपातकालीन |
| Call request | कॉल अनुरोध |
| Absence note | अनुपस्थिति नोट |
| Admit card / Progress report | एडमिट कार्ड / प्रगति रिपोर्ट |
| Timetable | समय-सारणी |
| Term / Topic / Grade | टर्म / टॉपिक / ग्रेड |
| Notifications / Privacy | नोटिफ़िकेशन / प्राइवेसी |
| Mark (a bus crew tap) | निशान |
| En route / Not started / Completed / Cancelled | रास्ते में / शुरू नहीं हुई / पूरी हुई / रद्द |
| Trip check | ट्रिप जाँच |
| Mother / Father / Other | माँ / पिता / अन्य |

## For the reviewer

- **Gender.** Sentences about a child use the masculine (बस में बैठा, उतरा,
  स्कूल नहीं आएगा), as the glossary's first draft did. A child may be a
  girl; a neutral plural form (बैठे, उतर गए) may read better. Decide once
  and it is a find-and-replace in `frontend/lib/l10n/parts/*_hi.json`.
- **Left in English on purpose:** anything the server writes (names,
  notices, holiday and fee names, server error messages), weekday and month
  names inside dates, the spoken next-stop prompt in the Bus app (needs a
  Hindi voice), and phone-settings paths in the battery help (they match
  the phone's own menus).
- Where to edit: `frontend/lib/l10n/parts/*_hi.json`, then
  `python tool/merge_arb.py` from `frontend/`.

