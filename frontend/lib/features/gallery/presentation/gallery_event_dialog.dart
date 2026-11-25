import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/gallery_providers.dart';
import '../data/gallery_models.dart';

const galleryTitleMax = 120;
const galleryDescriptionMax = 500;

bool galleryIsOffice(UserRole? role) =>
    role == UserRole.superAdmin || role == UserRole.groupAdmin || role == UserRole.schoolAdmin;

/// Posts an event, or changes one ([event]): its name, date, description and
/// who sees it - the whole school (admins only) or one class.
class GalleryEventDialog extends ConsumerStatefulWidget {
  const GalleryEventDialog({super.key, this.event});

  final GalleryEvent? event;

  @override
  ConsumerState<GalleryEventDialog> createState() => _GalleryEventDialogState();
}

class _GalleryEventDialogState extends ConsumerState<GalleryEventDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.event?.title);
  late final _description = TextEditingController(text: widget.event?.description);
  late DateTime _date = widget.event?.date ?? DateUtils.dateOnly(DateTime.now());
  late int? _sectionId = widget.event?.classSectionId;
  late int? _schoolId = widget.event?.schoolId;
  bool _saving = false;
  bool _triedSave = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save({required bool office}) async {
    if (_saving) return;
    setState(() => _triedSave = true);
    if (!_formKey.currentState!.validate() || (!office && _sectionId == null)) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final description = _description.text.trim();

    try {
      final saved = await ref
          .read(galleryEventsProvider.notifier)
          .save(
            GalleryEventDraft(
              title: _title.text.trim(),
              date: _date,
              description: description.isEmpty ? null : description,
              classSectionId: _sectionId,
              schoolId: _schoolId,
            ),
            id: widget.event?.id,
          );
      navigator.pop(saved);
      messenger.showSnackBar(SnackBar(content: Text(widget.event == null ? l10n.galleryPosted : l10n.gallerySaved)));
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.localizedMessage(context);
          _fieldErrors = {for (final e in failure.validationErrors.entries) e.key: e.value.first};
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colours = context.appColors;
    final user = ref.watch(authNotifierProvider).value;
    final office = galleryIsOffice(user?.role);
    final picksSchool = (user?.picksSchool ?? false) && widget.event == null;
    final sections = ref.watch(classSectionPickerProvider(picksSchool ? _schoolId : null));
    // A teacher posts only to a class they are the class teacher of.
    final options = [
      for (final option in sections.value ?? const <ClassSectionOption>[])
        if (office || option.classTeacherId == user?.id) option,
    ];

    return AlertDialog(
      title: Text(widget.event == null ? l10n.galleryNewEvent : l10n.galleryChangeEvent),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const Key('gallery-form-error'),
                    style: TextStyle(color: colours.danger),
                  ),
                  const SizedBox(height: 12),
                ],
                if (picksSchool) ...[
                  SchoolPicker(
                    selected: _schoolId,
                    onChanged: (value) => setState(() {
                      _schoolId = value;
                      _sectionId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  key: const Key('gallery-title'),
                  controller: _title,
                  maxLength: galleryTitleMax,
                  decoration: InputDecoration(
                    labelText: l10n.galleryTitleLabel,
                    hintText: l10n.galleryTitleHint,
                    errorText: _fieldErrors['title'],
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty ? l10n.galleryTitleRequired : null,
                ),
                const SizedBox(height: 6),
                InkWell(
                  key: const Key('gallery-date'),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.galleryDateLabel,
                      errorText: _fieldErrors['event_date'],
                      suffixIcon: const Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(formatDate(_date)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  key: ValueKey('gallery-audience-${options.length}'),
                  initialValue: options.any((o) => o.id == _sectionId) ? _sectionId : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.galleryWhoSees,
                    errorText:
                        _fieldErrors['class_section_id'] ??
                        (_triedSave && !office && _sectionId == null ? l10n.galleryChooseClass : null),
                    helperText: !office && options.isEmpty && !sections.isLoading ? l10n.galleryNoClassOfYours : null,
                  ),
                  items: [
                    if (office) DropdownMenuItem<int?>(value: null, child: Text(l10n.galleryWholeSchool)),
                    for (final option in options)
                      DropdownMenuItem<int?>(value: option.id, child: Text(l10n.galleryParentsOf(option.label))),
                  ],
                  onChanged: (value) => setState(() => _sectionId = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('gallery-description'),
                  controller: _description,
                  maxLength: galleryDescriptionMax,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.galleryDescriptionLabel,
                    errorText: _fieldErrors['description'],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          key: const Key('gallery-save'),
          onPressed: _saving ? null : () => _save(office: office),
          child: Text(widget.event == null ? l10n.galleryPost : l10n.gallerySave),
        ),
      ],
    );
  }
}
