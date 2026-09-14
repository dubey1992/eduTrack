/// One file, as the person chose it on their own machine.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}
