import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

bool get canPickFile => true;

/// Opens the browser's file chooser and reads what comes back.
///
/// The input is put on the page, hidden, and taken off again afterwards: a
/// detached input can be clicked but the browser opens no chooser for it.
/// [accept] is the same string the HTML attribute takes, e.g. '.csv,text/csv'.
///
/// Completes with null if the person closes the chooser without picking
/// anything - which the browser reports by simply never firing `change`, so
/// `cancel` is listened for as well.
Future<PickedFile?> pickFile({required String accept}) {
  final completer = Completer<PickedFile?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept
    ..style.display = 'none';

  web.document.body!.appendChild(input);

  void finish(PickedFile? file) {
    input.remove();
    if (!completer.isCompleted) completer.complete(file);
  }

  input.onchange = (web.Event _) {
    final files = input.files;

    if (files == null || files.length == 0) {
      finish(null);
      return;
    }

    final file = files.item(0)!;
    final reader = web.FileReader();

    reader.onload = (web.Event _) {
      final buffer = reader.result as JSArrayBuffer?;
      finish(
        buffer == null ? null : PickedFile(name: file.name, bytes: buffer.toDart.asUint8List().toList(growable: false)),
      );
    }.toJS;

    reader.onerror = ((web.Event _) => finish(null)).toJS;
    reader.readAsArrayBuffer(file);
  }.toJS;

  input.oncancel = ((web.Event _) => finish(null)).toJS;
  input.click();

  return completer.future;
}
