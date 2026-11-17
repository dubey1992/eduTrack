import 'models/grade_scale.dart';

/// Ready-made grading systems a school can start a scale from
/// (docs/document-styles.md). Every one only fills the form: the bands, the
/// points and the words stay the school's to change before it saves.
class GradeScalePreset {
  const GradeScalePreset({required this.name, required this.kind, required this.bands, this.gpaMultiplier});

  final String name;
  final GradeScaleKind kind;
  final List<GradeBand> bands;
  final String? gpaMultiplier;
}

GradeBand _band(String label, String min, String max, {bool failing = false, String? points, String? meaning}) =>
    GradeBand(
      id: null,
      label: label,
      minPercentage: min,
      maxPercentage: max,
      isFailing: failing,
      gradePoint: points,
      description: meaning,
    );

/// The presets, in the order the menu lists them.
final gradeScalePresets = <GradeScalePreset>[
  GradeScalePreset(
    name: 'Nine-point grades with grade points (CBSE style)',
    kind: GradeScaleKind.gpa,
    gpaMultiplier: '9.5',
    bands: [
      _band('A1', '91', '100', points: '10', meaning: 'Outstanding'),
      _band('A2', '81', '90.99', points: '9', meaning: 'Excellent'),
      _band('B1', '71', '80.99', points: '8', meaning: 'Very good'),
      _band('B2', '61', '70.99', points: '7', meaning: 'Good'),
      _band('C1', '51', '60.99', points: '6', meaning: 'Above average'),
      _band('C2', '41', '50.99', points: '5', meaning: 'Average'),
      _band('D', '33', '40.99', points: '4', meaning: 'Pass'),
      _band('E', '0', '32.99', failing: true, points: '0', meaning: 'Needs improvement'),
    ],
  ),
  GradeScalePreset(
    name: 'Four-point GPA (A to F)',
    kind: GradeScaleKind.gpa,
    bands: [
      _band('A', '90', '100', points: '4', meaning: 'Excellent'),
      _band('B', '80', '89.99', points: '3', meaning: 'Good'),
      _band('C', '70', '79.99', points: '2', meaning: 'Satisfactory'),
      _band('D', '60', '69.99', points: '1', meaning: 'Passing'),
      _band('F', '0', '59.99', failing: true, points: '0', meaning: 'Failing'),
    ],
  ),
  GradeScalePreset(
    name: 'Percentage with letter grades (A to F)',
    kind: GradeScaleKind.percentage,
    bands: [
      _band('A', '80', '100', meaning: 'Excellent'),
      _band('B', '65', '79.99', meaning: 'Good'),
      _band('C', '50', '64.99', meaning: 'Satisfactory'),
      _band('D', '33', '49.99', meaning: 'Pass'),
      _band('F', '0', '32.99', failing: true, meaning: 'Fail'),
    ],
  ),
  GradeScalePreset(
    name: 'Divisions (Distinction, First, Second, Third)',
    kind: GradeScaleKind.percentage,
    bands: [
      _band('Dist.', '75', '100', meaning: 'Distinction'),
      _band('First', '60', '74.99', meaning: 'First Division'),
      _band('Second', '45', '59.99', meaning: 'Second Division'),
      _band('Third', '33', '44.99', meaning: 'Third Division'),
      _band('Fail', '0', '32.99', failing: true, meaning: 'Not passed'),
    ],
  ),
  GradeScalePreset(
    name: 'Descriptive grades for young classes',
    kind: GradeScaleKind.grades,
    bands: [
      _band('A', '80', '100', meaning: 'Outstanding'),
      _band('B', '60', '79.99', meaning: 'Very good'),
      _band('C', '40', '59.99', meaning: 'Good'),
      _band('D', '0', '39.99', meaning: 'Needs support'),
    ],
  ),
];
