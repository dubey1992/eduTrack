import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/decimal_input_formatter.dart';
import '../../data/models/payment.dart';

/// What the Services section of a payment form holds: which of the fixed
/// services are ticked, their amounts, and the "other" fees typed by name.
///
/// A [ChangeNotifier] so the dialog can redraw the total and the remaining
/// balance as amounts are typed.
class PaymentServicesController extends ChangeNotifier {
  PaymentServicesController({List<PaymentItem> items = const []}) {
    for (final type in PaymentType.fixed) {
      _fixed[type] = _FixedLine(TextEditingController()..addListener(notifyListeners));
    }

    for (final item in items) {
      if (item.service == PaymentType.other) {
        _addOther(name: item.name ?? '', amount: _text(item.amount));
      } else {
        final line = _fixed[item.service]!;
        line.ticked = true;
        line.amount.text = _text(item.amount);
      }
    }
  }

  final Map<PaymentType, _FixedLine> _fixed = {};
  final List<_OtherLine> _others = [];

  static String _text(double amount) => amount.toStringAsFixed(2);

  bool isTicked(PaymentType type) => _fixed[type]!.ticked;

  TextEditingController amountOf(PaymentType type) => _fixed[type]!.amount;

  List<({TextEditingController name, TextEditingController amount})> get others => [
    for (final line in _others) (name: line.name, amount: line.amount),
  ];

  void setTicked(PaymentType type, bool ticked) {
    _fixed[type]!.ticked = ticked;
    notifyListeners();
  }

  void addOther() {
    _addOther();
    notifyListeners();
  }

  void _addOther({String name = '', String amount = ''}) {
    _others.add(
      _OtherLine(TextEditingController(text: name), TextEditingController(text: amount)..addListener(notifyListeners)),
    );
  }

  void removeOther(int index) {
    _others.removeAt(index).dispose();
    notifyListeners();
  }

  /// True once anything at all is on the payment.
  bool get hasAny => _fixed.values.any((line) => line.ticked) || _others.isNotEmpty;

  /// The sum of every amount that can be read so far.
  double get total {
    var sum = 0.0;
    for (final line in _fixed.values) {
      if (line.ticked) sum += double.tryParse(line.amount.text) ?? 0;
    }
    for (final line in _others) {
      sum += double.tryParse(line.amount.text) ?? 0;
    }

    return sum;
  }

  /// The lines to send - read once the form has validated them.
  List<PaymentItem> get items => [
    for (final type in PaymentType.fixed)
      if (_fixed[type]!.ticked) PaymentItem(service: type, amount: double.parse(_fixed[type]!.amount.text)),
    for (final line in _others)
      PaymentItem(service: PaymentType.other, name: line.name.text.trim(), amount: double.parse(line.amount.text)),
  ];

  @override
  void dispose() {
    for (final line in _fixed.values) {
      line.amount.dispose();
    }
    for (final line in _others) {
      line.dispose();
    }
    super.dispose();
  }
}

class _FixedLine {
  _FixedLine(this.amount);

  final TextEditingController amount;
  bool ticked = false;
}

class _OtherLine {
  _OtherLine(this.name, this.amount);

  final TextEditingController name;
  final TextEditingController amount;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

String? validateServiceAmount(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null || parsed <= 0) return 'Enter an amount';

  return null;
}

/// The Services section: tick a service and its amount box opens beside it;
/// add "other" fees by name; the total adds itself up underneath.
class PaymentServicesField extends StatelessWidget {
  const PaymentServicesField({super.key, required this.controller, required this.currencyCode});

  final PaymentServicesController controller;

  /// The school's currency, for the total. Empty until a school is chosen.
  final String currencyCode;

  static const _amountWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => FormField<void>(
        // Nothing ticked is caught here, before anything is sent.
        validator: (_) => controller.hasAny ? null : 'Choose at least one service',
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Services', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final type in PaymentType.fixed) _fixedRow(context, type),
            const SizedBox(height: 8),
            Text('Other fees', style: theme.textTheme.titleSmall),
            for (final (index, line) in controller.others.indexed) _otherRow(index, line.name, line.amount),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add-other-fee'),
                onPressed: controller.addOther,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add other fee'),
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(field.errorText!, style: TextStyle(color: context.appColors.danger, fontSize: 12)),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Total', style: theme.textTheme.titleMedium)),
                Text(
                  currencyCode.isEmpty
                      ? controller.total.toStringAsFixed(2)
                      : formatCurrency(controller.total, currencyCode),
                  key: const Key('services-total'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixedRow(BuildContext context, PaymentType type) {
    final ticked = controller.isTicked(type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => controller.setTicked(type, !ticked),
              child: Row(
                children: [
                  Checkbox(value: ticked, onChanged: (value) => controller.setTicked(type, value ?? false)),
                  Flexible(child: Text(type.label)),
                ],
              ),
            ),
          ),
          // The amount box opens only for a ticked service.
          if (ticked)
            SizedBox(
              width: _amountWidth,
              child: TextFormField(
                key: Key('amount-${type.apiValue}'),
                controller: controller.amountOf(type),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [DecimalTextInputFormatter()],
                decoration: const InputDecoration(labelText: 'Amount', isDense: true),
                validator: validateServiceAmount,
              ),
            ),
        ],
      ),
    );
  }

  Widget _otherRow(int index, TextEditingController name, TextEditingController amount) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: Key('other-name-$index'),
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Fee name', isDense: true, counterText: ''),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Say what this fee is for' : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _amountWidth,
            child: TextFormField(
              key: Key('other-amount-$index'),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [DecimalTextInputFormatter()],
              decoration: const InputDecoration(labelText: 'Amount', isDense: true),
              validator: validateServiceAmount,
            ),
          ),
          IconButton(
            key: Key('remove-other-$index'),
            tooltip: 'Remove this fee',
            onPressed: () => controller.removeOther(index),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
