/// Which year of school a class is (docs/onboarding.md). Mirrors the server's
/// `school/class_levels.py`: the server works the level out from the name
/// too, so this only saves the person a pick.
///
/// Playgroup -3, Nursery -2, LKG -1, UKG 0, Class 1 ... Class 12 = 1 ... 12.
const int lowestClassLevel = -3;
const int highestClassLevel = 12;

final List<(String, int)> standardClassLevels = List.unmodifiable(<(String, int)>[
  ('Playgroup', -3),
  ('Nursery', -2),
  ('LKG', -1),
  ('UKG', 0),
  for (var n = 1; n <= highestClassLevel; n++) ('Class $n', n),
]);

/// "LKG" for -1, "Class 7" for 7.
String classLevelLabel(int level) {
  for (final (name, value) in standardClassLevels) {
    if (value == level) return name;
  }
  return 'Level $level';
}

/// "Nursery - Class 10" for a subject taught across a range of years.
String classLevelRange(int from, int to) =>
    from == to ? classLevelLabel(from) : '${classLevelLabel(from)} - ${classLevelLabel(to)}';

const Map<String, int> _prePrimary = {
  'playgroup': -3, 'playschool': -3, 'pg': -3, 'prenursery': -3, 'toddler': -3, //
  'nursery': -2, 'nur': -2,
  'lkg': -1, 'kg1': -1, 'lowerkg': -1, 'lowerkindergarten': -1, 'junkg': -1, 'juniorkg': -1, 'prep1': -1,
  'ukg': 0, 'kg2': 0, 'upperkg': 0, 'upperkindergarten': 0, 'senkg': 0, 'seniorkg': 0, 'kg': 0,
  'kindergarten': 0, 'reception': 0, 'prep': 0, 'prep2': 0,
};

const Map<String, int> _roman = {
  'i': 1,
  'ii': 2,
  'iii': 3,
  'iv': 4,
  'v': 5,
  'vi': 6,
  'vii': 7,
  'viii': 8,
  'ix': 9,
  'x': 10,
  'xi': 11,
  'xii': 12,
};

final RegExp _numbered = RegExp(r'^(?:(?:class|grade|std|standard|year|yr)\s*)?(\d{1,2}|[ivx]{1,4})(?:st|nd|rd|th)?$');

/// The level a class's name says - "LKG", "Class 7", "Std VII" - or null
/// when it says nothing, and then the person picks.
int? classLevelFromName(String name) {
  final text = name.toLowerCase().replaceAll('.', ' ').replaceAll('-', ' ').split(RegExp(r'\s+')).join(' ').trim();
  final squeezed = text.replaceAll(' ', '');

  final prePrimary = _prePrimary[squeezed];
  if (prePrimary != null) return prePrimary;

  final match = _numbered.firstMatch(text);
  if (match == null) return null;

  final number = match.group(1)!;
  final level = int.tryParse(number) ?? _roman[number];

  return level != null && level >= 1 && level <= highestClassLevel ? level : null;
}
