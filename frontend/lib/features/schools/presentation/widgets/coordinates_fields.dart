import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Latitude and longitude for a school, side by side.
///
/// Optional - most schools are onboarded without one - but the pair goes
/// together: half a coordinate points nowhere, so the API refuses one without
/// the other and these say so before the form is sent.
class CoordinatesFields extends StatelessWidget {
  const CoordinatesFields({super.key, required this.latitude, required this.longitude});

  final TextEditingController latitude;
  final TextEditingController longitude;

  /// A coordinate is a signed decimal; nothing else belongs in the box.
  static final _allowed = FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*'));

  String? _validate(
    String? value, {
    required TextEditingController other,
    required double limit,
    required String name,
  }) {
    final text = (value ?? '').trim();
    final otherText = other.text.trim();

    if (text.isEmpty) {
      return otherText.isEmpty ? null : 'Enter a $name too, or clear the other box.';
    }

    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter a $name as a number.';
    if (parsed < -limit || parsed > limit) return 'A $name is between -$limit and $limit.';

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: latitude,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [_allowed],
            decoration: const InputDecoration(labelText: 'Latitude (optional)', hintText: '18.5204'),
            validator: (value) => _validate(value, other: longitude, limit: 90, name: 'latitude'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: longitude,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [_allowed],
            decoration: const InputDecoration(labelText: 'Longitude (optional)', hintText: '73.8567'),
            validator: (value) => _validate(value, other: latitude, limit: 180, name: 'longitude'),
          ),
        ),
      ],
    );
  }
}
