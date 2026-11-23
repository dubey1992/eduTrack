/// One file, as the person chose it on their own machine.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// One of several files chosen at once, not yet read.
///
/// Reading is left until it is needed because a whole class's photos - five
/// hundred files of a few megabytes each - would not fit in a browser tab's
/// memory at once. The name and size are known straight away; [read] fetches
/// the bytes when the file's turn comes (docs/student-photos.md, P2).
class ChosenFile {
  const ChosenFile({required this.name, required this.size, required this.read});

  final String name;

  /// In bytes.
  final int size;

  final Future<List<int>> Function() read;
}
