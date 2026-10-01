import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/marketing/data/marketing_draft_repository.dart';
import 'package:edutrack_app/features/marketing/data/models/marketing_draft.dart';

/// Test double for [MarketingDraftRepository] - keeps the one row the way
/// the server would, and records what each save was asked for.
class FakeMarketingDraftRepository implements MarketingDraftRepository {
  FakeMarketingDraftRepository({
    Map<String, String>? draft,
    Map<String, String>? published,
    this.publishedAt,
    this.failGetWith,
    this.failSaveWith,
    this.failPublishWith,
  }) : draft = draft ?? const {},
       published = published ?? const {};

  Map<String, String> draft;
  Map<String, String> published;
  DateTime? publishedAt;

  Failure? failGetWith;
  Failure? failSaveWith;
  Failure? failPublishWith;

  /// When set, [get] waits on it - so a test can look at the loading state.
  Completer<void>? getGate;

  /// The same, for a save that is still in flight.
  Completer<void>? saveGate;

  int getCalls = 0;
  int saveCalls = 0;
  int publishCalls = 0;
  Map<String, String>? lastSave;

  MarketingDraft get current => MarketingDraft(
    sections: marketingSections,
    draft: draft,
    published: published,
    publishedAt: publishedAt,
    hasUnpublishedChanges: !_sameWords(draft, published),
  );

  @override
  Future<MarketingDraft> get() async {
    getCalls++;
    if (getGate != null) await getGate!.future;
    if (failGetWith != null) throw failGetWith!;
    return current;
  }

  @override
  Future<MarketingDraft> save(Map<String, String> document) async {
    saveCalls++;
    lastSave = Map.of(document);
    if (saveGate != null) await saveGate!.future;
    if (failSaveWith != null) throw failSaveWith!;

    draft = Map.of(document);
    return current;
  }

  @override
  Future<void> publish() async {
    publishCalls++;
    if (failPublishWith != null) throw failPublishWith!;

    published = Map.of(draft);
    publishedAt = DateTime(2026, 10, 1, 9, 30);
  }

  static bool _sameWords(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    return a.entries.every((entry) => b[entry.key] == entry.value);
  }
}

/// A slice of what the server declares - enough to draw a form with a
/// single-line field, a multiline one and a second section, without
/// restating all seven sections of the real page.
const marketingSections = [
  MarketingSection(
    key: 'hero',
    label: 'The opening',
    description: 'The headline and the first paragraph anybody reads.',
    fields: [
      MarketingField(
        key: 'hero.headline',
        label: 'Headline',
        multiline: false,
        maxLength: 90,
        help: 'Set large, beside the dashboard picture.',
      ),
      MarketingField(key: 'hero.body', label: 'Opening paragraph', multiline: true, maxLength: 300, help: ''),
    ],
  ),
  MarketingSection(
    key: 'cta',
    label: 'The invitation',
    description: 'The blue band near the bottom.',
    fields: [MarketingField(key: 'cta.button', label: 'Button', multiline: false, maxLength: 32, help: '')],
  ),
];
