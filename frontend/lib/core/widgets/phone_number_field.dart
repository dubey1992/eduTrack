import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/country_dial_code.dart';

/// A phone-number input that pairs a country dial-code picker with the
/// local number, composing both into a single `"+code number"` string on
/// [controller] - the shape every phone/mobile column already stores, so no
/// other integration point (submit handlers, API payloads) needs to change.
/// The selected country also caps how many digits can be typed and what
/// counts as valid - e.g. India expects exactly 10 digits, Singapore 8.
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({super.key, required this.controller, required this.label, this.required = false});

  /// Holds the full composed value, e.g. "+91 9876543210".
  final TextEditingController controller;
  final String label;
  final bool required;

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  late String _selectedIso2;
  late final TextEditingController _numberController;

  CountryDialCode get _country => CountryDialCode.common.firstWhere((c) => c.iso2 == _selectedIso2);

  @override
  void initState() {
    super.initState();
    final match = CountryDialCode.matchPrefix(widget.controller.text.trim());
    _selectedIso2 = match?.iso2 ?? CountryDialCode.common.first.iso2;
    _numberController = TextEditingController(
      text: match == null
          ? widget.controller.text.trim()
          : widget.controller.text.trim().substring(match.dialCode.length + 1),
    )..addListener(_syncController);
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _syncController() {
    final number = _numberController.text.trim();
    widget.controller.text = number.isEmpty ? '' : '${_country.dialCode} $number';
  }

  @override
  Widget build(BuildContext context) {
    final country = _country;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedIso2,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Code'),
            items: [
              for (final c in CountryDialCode.common)
                DropdownMenuItem(
                  value: c.iso2,
                  child: Text('${c.flag} ${c.dialCode} ${c.iso2}', overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
            ],
            onChanged: (iso2) {
              setState(() => _selectedIso2 = iso2!);
              _syncController();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _numberController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(country.maxLength),
            ],
            decoration: InputDecoration(labelText: widget.label),
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return widget.required ? '${widget.label} is required' : null;
              if (trimmed.length < country.minLength || trimmed.length > country.maxLength) {
                return country.minLength == country.maxLength
                    ? '${country.countryName} numbers are ${country.minLength} digits'
                    : '${country.countryName} numbers are ${country.minLength}-${country.maxLength} digits';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }
}
