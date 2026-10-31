import 'package:edutrack_app/features/classes/data/class_levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pre-primary names come before Class 1', () {
    expect(classLevelFromName('Playgroup'), -3);
    expect(classLevelFromName('Nursery'), -2);
    expect(classLevelFromName('LKG'), -1);
    expect(classLevelFromName('KG 1'), -1);
    expect(classLevelFromName('UKG'), 0);
    expect(classLevelFromName('Upper K.G.'), 0);
  });

  test('numbered names in the ways schools write them', () {
    for (final name in ['Class 7', 'Grade 7', 'Std. VII', 'Standard 7', '7th', '7', 'class vii']) {
      expect(classLevelFromName(name), 7, reason: name);
    }
  });

  test('a name that says nothing gives nothing', () {
    for (final name in ['Rose', 'Class 13', 'Class 0', '', 'Senior Batch']) {
      expect(classLevelFromName(name), isNull, reason: name);
    }
  });

  test('labels and ranges read as class names', () {
    expect(classLevelLabel(-1), 'LKG');
    expect(classLevelLabel(7), 'Class 7');
    expect(classLevelRange(-2, 10), 'Nursery - Class 10');
    expect(classLevelRange(5, 5), 'Class 5');
  });
}
