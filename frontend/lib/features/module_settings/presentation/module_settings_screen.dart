import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/school_picker.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/module_settings_notifier.dart';
import '../data/models/module_setting.dart';

/// Which modules a school has, and each module's own settings. A Super Admin
/// picks the school and holds the platform switch; a School Admin sees their
/// own school and the switch the school holds.
class ModuleSettingsScreen extends ConsumerWidget {
  const ModuleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    return _ModuleSettingsBody(picksSchool: actor.role == UserRole.superAdmin);
  }
}

class _ModuleSettingsBody extends ConsumerStatefulWidget {
  const _ModuleSettingsBody({required this.picksSchool});

  /// True for a Super Admin, who belongs to no school and has to say which
  /// one. Everybody else configures their own, which the server fills in.
  final bool picksSchool;

  @override
  ConsumerState<_ModuleSettingsBody> createState() => _ModuleSettingsBodyState();
}

class _ModuleSettingsBodyState extends ConsumerState<_ModuleSettingsBody> {
  int? _schoolId;

  @override
  Widget build(BuildContext context) {
    final needsSchool = widget.picksSchool && _schoolId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Module Settings',
          actions: [
            if (widget.picksSchool)
              SizedBox(
                width: 260,
                child: SchoolPicker(
                  selected: _schoolId,
                  required: false,
                  onChanged: (schoolId) => setState(() => _schoolId = schoolId),
                ),
              ),
          ],
        ),
        Expanded(
          child: needsSchool
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Pick a school to configure its modules.')),
                    ),
                  ),
                )
              : _ModuleList(schoolId: _schoolId),
        ),
      ],
    );
  }
}

class _ModuleList extends ConsumerWidget {
  const _ModuleList({required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<ModuleSetting>>(
      value: ref.watch(moduleSettingsNotifierProvider(schoolId)),
      onRetry: () => ref.read(moduleSettingsNotifierProvider(schoolId).notifier).load(),
      isEmpty: (rows) => rows.isEmpty,
      emptyBuilder: (context) => const Center(child: Text('No modules are registered.')),
      data: (context, rows) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final setting = rows[index];
          return Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _ModuleCard(key: ValueKey('module-card-${setting.module}'), schoolId: schoolId, setting: setting),
            ),
          );
        },
      ),
    );
  }
}

/// One module: its switches, which save the moment they move, and its
/// settings, which save on the button.
class _ModuleCard extends ConsumerStatefulWidget {
  const _ModuleCard({super.key, required this.schoolId, required this.setting});

  final int? schoolId;
  final ModuleSetting setting;

  @override
  ConsumerState<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends ConsumerState<_ModuleCard> {
  final _formKey = GlobalKey<FormState>();

  /// The form's working copy of the settings: bools as bools, ints as the
  /// text typed, so a half-typed number is not lost on rebuild.
  final _flags = <String, bool>{};
  final _numbers = <String, TextEditingController>{};

  bool _switching = false;
  bool _saving = false;
  String? _switchError;
  String? _settingsError;

  ModuleSetting get setting => widget.setting;

  @override
  void initState() {
    super.initState();
    _seedForm();
  }

  @override
  void didUpdateWidget(covariant _ModuleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A saved row comes back with the server's values; the form follows.
    // A switch save leaves the settings alone, and so does this.
    if (!mapEquals(oldWidget.setting.settings, widget.setting.settings)) _seedForm();
  }

  @override
  void dispose() {
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seedForm() {
    for (final field in setting.settingsSchema) {
      final value = setting.valueOf(field);
      switch (field.type) {
        case SettingFieldType.flag:
          _flags[field.key] = value == true;
        case SettingFieldType.integer:
          final text = value == null ? '' : '$value';
          final existing = _numbers[field.key];
          if (existing == null) {
            _numbers[field.key] = TextEditingController(text: text)..addListener(() => setState(() {}));
          } else {
            existing.text = text;
          }
      }
    }
  }

  bool get _isDirty {
    for (final field in setting.settingsSchema) {
      final value = setting.valueOf(field);
      switch (field.type) {
        case SettingFieldType.flag:
          if (_flags[field.key] != (value == true)) return true;
        case SettingFieldType.integer:
          if (_numbers[field.key]!.text.trim() != (value == null ? '' : '$value')) return true;
      }
    }
    return false;
  }

  /// The school switch is the school's to move, except when the platform
  /// has withdrawn the module - then there is nothing to switch on.
  bool get _schoolSwitchLocked => !setting.switchable || (!setting.platformEnabled && !setting.canChangePlatform);

  Future<void> _moveSwitch({bool? platformEnabled, bool? schoolEnabled}) async {
    if (_switching) return;

    final turningOff = platformEnabled == false || schoolEnabled == false;
    if (turningOff) {
      final confirmed = await confirmDialog(
        context,
        title: platformEnabled == false ? 'Withdraw ${setting.label}?' : 'Switch off ${setting.label}?',
        message: platformEnabled == false
            ? 'Withdraw ${setting.label} from this school? Its screens and API are refused until it is granted '
                  'again; nothing is deleted.'
            : 'Switch off ${setting.label} for this school? Its screens and API are refused until it is on again; '
                  'nothing is deleted.',
        confirmLabel: platformEnabled == false ? 'Withdraw' : 'Switch off',
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _switching = true;
      _switchError = null;
    });

    try {
      await ref
          .read(moduleSettingsNotifierProvider(widget.schoolId).notifier)
          .updateSwitch(setting.module, platformEnabled: platformEnabled, schoolEnabled: schoolEnabled);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      final errors = failure.validationErrors;
      if (mounted) {
        setState(() {
          _switchError = errors['platform_enabled']?.first ?? errors['school_enabled']?.first ?? failure.message;
        });
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Map<String, Object?> _settingsToSend() {
    return {
      for (final field in setting.settingsSchema)
        field.key: switch (field.type) {
          SettingFieldType.flag => _flags[field.key] ?? false,
          SettingFieldType.integer => int.parse(_numbers[field.key]!.text.trim()),
        },
    };
  }

  Future<void> _saveSettings() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _settingsError = null;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(moduleSettingsNotifierProvider(widget.schoolId).notifier)
          .saveSettings(setting.module, _settingsToSend());

      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() => _settingsError = failure.validationErrors['settings']?.join(' ') ?? failure.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final module = setting.module;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(setting.label, style: Theme.of(context).textTheme.titleMedium),
                if (!setting.switchable)
                  const StatusBadge(label: 'Always on', tone: BadgeTone.neutral)
                else if (!setting.platformEnabled && !setting.canChangePlatform)
                  const StatusBadge(label: 'Not granted by the platform', tone: BadgeTone.neutral)
                else if (!setting.enabled)
                  const StatusBadge(label: 'Off', tone: BadgeTone.warning),
              ],
            ),
            if (setting.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(setting.description, style: TextStyle(fontSize: 13, color: colors.muted)),
            ],
            const SizedBox(height: 8),
            if (setting.canChangePlatform)
              SwitchListTile(
                key: Key('module-platform-$module'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Platform'),
                subtitle: const Text('Granted to this school by the platform'),
                value: setting.platformEnabled,
                onChanged: setting.switchable && !_switching ? (value) => _moveSwitch(platformEnabled: value) : null,
              ),
            SwitchListTile(
              key: Key('module-school-$module'),
              contentPadding: EdgeInsets.zero,
              title: const Text('On for this school'),
              subtitle: setting.switchable ? null : const Text('Part of the spine; it cannot be switched off'),
              // The spine is always on, whatever a stray row says.
              value: !setting.switchable || setting.schoolEnabled,
              onChanged: _schoolSwitchLocked || _switching ? null : (value) => _moveSwitch(schoolEnabled: value),
            ),
            if (_switchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _switchError!,
                  key: Key('module-switch-error-$module'),
                  style: TextStyle(fontSize: 13, color: colors.danger),
                ),
              ),
            if (setting.hasSettings) ...[const Divider(height: 24), _buildSettingsForm(context)],
            if (setting.updatedByName != null) ...[
              const SizedBox(height: 8),
              Text('Updated by ${setting.updatedByName}', style: TextStyle(fontSize: 13, color: colors.muted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsForm(BuildContext context) {
    final colors = context.appColors;
    final module = setting.module;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in setting.settingsSchema)
            switch (field.type) {
              SettingFieldType.flag => SwitchListTile(
                key: Key('module-setting-$module-${field.key}'),
                contentPadding: EdgeInsets.zero,
                title: Text(field.label),
                subtitle: field.help == null ? null : Text(field.help!),
                value: _flags[field.key] ?? false,
                onChanged: _saving ? null : (value) => setState(() => _flags[field.key] = value),
              ),
              SettingFieldType.integer => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  key: Key('module-setting-$module-${field.key}'),
                  controller: _numbers[field.key],
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: field.label, helperText: field.help, helperMaxLines: 3),
                  validator: (value) => _validateNumber(field, value),
                ),
              ),
            },
          if (_settingsError != null) ...[
            Text(
              _settingsError!,
              key: Key('module-settings-error-$module'),
              style: TextStyle(fontSize: 13, color: colors.danger),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: Key('module-save-$module'),
              onPressed: _isDirty && !_saving ? _saveSettings : null,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  static String? _validateNumber(SettingField field, String? value) {
    final number = int.tryParse((value ?? '').trim());
    if (number == null) return '${field.label} must be a whole number';
    if (field.min != null && number < field.min!) return '${field.label} must be at least ${field.min}';
    if (field.max != null && number > field.max!) return '${field.label} must be at most ${field.max}';
    return null;
  }
}
