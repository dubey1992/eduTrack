import '../../transport/data/models/transport_trip.dart';

/// Finds children on the trip sheet by what the crew knows about them: a
/// name, part of one, an admission number, a class (docs/driver-app.md, D8).
///
/// Forgiving on purpose. The query may have been spoken, and a recogniser
/// hears "Sai Iyer" as "Sai Ayer" and "Kabir" as "Kabeer" often enough; it
/// may have been typed on a moving bus with one thumb. So a word matches
/// when it starts a word of the child's, or when it is a letter or two away
/// from one - one for words of four or five letters, two from six, nothing
/// for shorter words or "Sai" would find half the bus. Every word asked for
/// has to land somewhere.
bool riderMatches(TripRider rider, String query) {
  final asked = _words(query);
  if (asked.isEmpty) return true;

  final known = [
    ..._words(rider.name),
    ..._words(rider.admissionNumber),
    if (rider.classSectionName != null) ..._words(rider.classSectionName!),
  ];

  return asked.every((word) => known.any((candidate) => _close(candidate, word)));
}

/// The riders that match, in the order given.
List<TripRider> findRiders(Iterable<TripRider> riders, String query) {
  return [
    for (final rider in riders)
      if (riderMatches(rider, query)) rider,
  ];
}

List<String> _words(String text) {
  return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').split(' ').where((word) => word.isNotEmpty).toList();
}

bool _close(String known, String asked) {
  if (known.startsWith(asked)) return true;
  final allowed = _slack(asked);
  if (allowed == 0 || known.length < 4) return false;
  if ((known.length - asked.length).abs() > allowed) return false;
  return _editDistance(known, asked) <= allowed;
}

/// How many letters a word may be off by and still count.
int _slack(String word) => switch (word.length) {
  < 4 => 0,
  < 6 => 1,
  _ => 2,
};

/// Levenshtein distance - the number of single-letter edits between two
/// words. Only ever asked of two short words, so the plain table is fine.
int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (j) => j);

  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      current[j] = [previous[j] + 1, current[j - 1] + 1, substitution].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }

  return previous[b.length];
}
