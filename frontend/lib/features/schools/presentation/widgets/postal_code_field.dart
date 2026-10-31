import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../maps/data/places_repository.dart';

/// The postal code box of the school form, which fills in the rest of the
/// address once somebody types a code (docs/maps.md, postal codes).
///
/// A short pause after typing, it asks the server what the code belongs to
/// and fills in the city, state, country and the map position. It only ever
/// fills a box that is empty or that it filled itself, so nothing a person
/// typed is overwritten. The street address stays theirs to type: a postal
/// code covers many streets.
///
/// An existing code is not looked up when the form opens - only a code
/// somebody types.
class PostalCodeField extends ConsumerStatefulWidget {
  const PostalCodeField({
    super.key,
    required this.postalCode,
    required this.city,
    required this.state,
    required this.country,
    required this.latitude,
    required this.longitude,
    this.validator,
  });

  final TextEditingController postalCode;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController country;
  final TextEditingController latitude;
  final TextEditingController longitude;
  final FormFieldValidator<String>? validator;

  @override
  ConsumerState<PostalCodeField> createState() => _PostalCodeFieldState();
}

class _PostalCodeFieldState extends ConsumerState<PostalCodeField> {
  /// Long enough that a code is looked up once somebody stops typing, not
  /// once per digit.
  static const _pause = Duration(milliseconds: 700);

  /// No postal code anywhere is shorter.
  static const _shortest = 3;

  Timer? _typing;
  bool _looking = false;
  String? _note;
  bool _noteIsProblem = false;

  /// The code last asked about - the form's own code when it opens, so an
  /// existing school is never looked up just by being edited. Set in
  /// [initState], not lazily: a lazy read would happen only after the first
  /// keystroke had already changed the box, and the typed code would look
  /// as if it had been asked about.
  late String _asked;

  /// What this field put in each box, so it may replace its own words but
  /// never somebody else's.
  final Map<TextEditingController, String> _filled = {};

  @override
  void initState() {
    super.initState();
    _asked = widget.postalCode.text.trim();
  }

  @override
  void dispose() {
    _typing?.cancel();
    super.dispose();
  }

  void _changed(String value) {
    _typing?.cancel();
    final code = value.trim();

    if (code.length < _shortest || code == _asked) {
      if (_note != null || _looking) {
        setState(() {
          _note = null;
          _looking = false;
        });
      }
      return;
    }

    _typing = Timer(_pause, () => _lookUp(code));
  }

  Future<void> _lookUp(String code) async {
    setState(() {
      _looking = true;
      _note = null;
    });

    final result = await ref.read(placesRepositoryProvider).lookUpPostalCode(code, country: widget.country.text);

    // Somebody kept typing while the answer was on its way.
    if (!mounted || widget.postalCode.text.trim() != code) return;

    _asked = code;
    setState(() {
      _looking = false;
      switch (result.outcome) {
        case PostalLookupOutcome.found:
          _note = _fillFrom(result.place!);
          _noteIsProblem = false;
        case PostalLookupOutcome.notFound:
          _note = 'No place found for this postal code. Check it, or type the address in.';
          _noteIsProblem = true;
        case PostalLookupOutcome.unavailable:
          _note = "Postal code lookup isn't available right now - type the address in.";
          _noteIsProblem = false;
      }
    });
  }

  /// Fills what it may, and says what it did.
  String _fillFrom(PostalPlace place) {
    final filled = <String>[
      if (_fill(widget.city, place.city)) 'city',
      if (_fill(widget.state, place.state)) 'state',
      if (_fill(widget.country, place.country)) 'country',
    ];

    final pinned =
        _fill(widget.latitude, place.latitude.toStringAsFixed(7)) &
        _fill(widget.longitude, place.longitude.toStringAsFixed(7));
    if (pinned) filled.add('map pin');

    if (filled.isEmpty) return '${place.place}. What you typed was kept.';

    return '${place.place} - filled in the ${_listed(filled)}. Check them before saving.';
  }

  bool _fill(TextEditingController box, String value) {
    if (value.isEmpty) return false;

    final current = box.text.trim();
    if (current.isNotEmpty && current != _filled[box]) return false;

    box.text = value;
    _filled[box] = value;
    return true;
  }

  static String _listed(List<String> parts) {
    if (parts.length == 1) return parts.single;

    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextFormField(
      key: const Key('school-postal-code'),
      controller: widget.postalCode,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'Postal code',
        helperText: _looking ? 'Looking up this postal code...' : _note,
        helperMaxLines: 3,
        helperStyle: _noteIsProblem && !_looking ? TextStyle(color: scheme.error) : null,
        suffixIcon: _looking
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      onChanged: _changed,
      onFieldSubmitted: (value) {
        final code = value.trim();
        if (code.length >= _shortest && code != _asked) {
          _typing?.cancel();
          _lookUp(code);
        }
      },
      validator: widget.validator,
    );
  }
}
