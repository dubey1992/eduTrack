import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../transport/data/models/transport_trip.dart';
import '../../application/location_sharing_notifier.dart';
import '../../application/trip_detail_notifier.dart';
import '../../application/trip_mark_queue.dart';
import '../../data/offline_start.dart';
import '../../data/map_navigator.dart';
import '../../data/navigation_session.dart';
import '../../data/rider_search.dart';
import '../../data/trip_voice.dart';
import '../navigate_screen.dart';
import '../trip_words.dart';
import '../../data/models/not_sent_mark.dart';
import 'bulk_mark_sheet.dart';
import 'location_sharing_tile.dart';
import 'not_sent_card.dart';
import 'rider_search_field.dart';
import 'rider_tile.dart';
import 'sos_button.dart';
import 'trip_screen_hold.dart';

/// One trip, stop by stop, with each stop's children under it.
///
/// Every tap is a mark: it shows at once and waits on the phone until it
/// reaches the server (see TripMarkQueue), so nothing here waits on signal.
class RunningTripView extends ConsumerStatefulWidget {
  const RunningTripView({super.key, required this.tripId, required this.onBack});

  final int tripId;
  final VoidCallback onBack;

  @override
  ConsumerState<RunningTripView> createState() => _RunningTripViewState();
}

class _RunningTripViewState extends ConsumerState<RunningTripView> {
  /// A second tap this soon after the last is taken as the same tap - on a
  /// moving bus a double tap is easy, and the next button may sit under it.
  static const _tapGap = Duration(milliseconds: 400);

  /// Running while taps are being ignored.
  Timer? _tapCooldown;

  /// What the crew typed or said into the search box. Empty is the whole
  /// sheet; anything else narrows the stops and children to the ones that
  /// match (rider_search.dart).
  String _query = '';

  /// This sheet's own snackbars, shown above the SOS / End trip bar rather
  /// than over it.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  ScaffoldMessengerState? get _snackBars => _messenger.currentState;

  TripDetailNotifier get _trip => ref.read(tripDetailProvider(widget.tripId).notifier);

  bool _acceptTap() {
    if (_tapCooldown?.isActive ?? false) return false;
    _tapCooldown = Timer(_tapGap, () {});
    return true;
  }

  /// The trips whose next stop has been said aloud since the app opened, so
  /// coming back to the sheet does not say it again (M7, 3.2).
  static final Set<int> _announced = {};

  /// Says the next stop the first time this trip is shown running, once
  /// the trip has loaded.
  void _announceOnce(TransportTrip trip) {
    if (!trip.isInProgress || !_announced.add(trip.id)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _trip.announceNextStop();
    });
  }

  @override
  void dispose() {
    _tapCooldown?.cancel();
    super.dispose();
  }

  /// "Running late" (M7, 5.5): 10, 15 or 30 minutes, one tap each - no
  /// typing on a moving bus.
  Future<void> _late() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.busRunningLateQuestion, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(context.l10n.busRunningLateHelp, style: TextStyle(color: context.appColors.muted)),
              const SizedBox(height: 16),
              for (final choice in TripDetailNotifier.delayChoices) ...[
                ConstrainedBox(
                  // A minimum, not a fixed height: the label grows with large text (M11, 3.4).
                  constraints: const BoxConstraints(minHeight: 52),
                  child: FilledButton.tonal(
                    key: Key('trip-late-$choice'),
                    onPressed: () => Navigator.of(context).pop(choice),
                    child: Text(context.l10n.busLateMinutes(choice), style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
    if (minutes == null || !mounted) return;

    await _trip.reportDelay(minutes);
    if (!mounted) return;
    _snackBars
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.busParentsToldLate(minutes))));
  }

  Future<void> _callParent(TripRider rider) async {
    final opened = await _trip.callParent(rider);
    if (!opened && mounted) {
      _snackBars
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.busNoDialler)));
    }
  }

  /// Takes the crew to the next stop. Only ever offered for a stop that has
  /// a position, so there is no "where?" to answer here.
  ///
  /// Guidance inside the app where the Navigation SDK will have it, and the
  /// Google Maps hand-off where it will not - the screen decides, because
  /// only it knows which way it went (docs/driver-app.md, D7).
  Future<void> _navigateTo(TripStop stop) async {
    final latitude = double.tryParse(stop.latitude ?? '');
    final longitude = double.tryParse(stop.longitude ?? '');
    if (latitude == null || longitude == null) return;

    final inApp = await ref.read(navigationSessionProvider).isSupported();
    if (!mounted) return;

    if (inApp) {
      await context.push(
        '/navigate',
        extra: NavigateTo(latitude: latitude, longitude: longitude, stopName: stop.name),
      );
      return;
    }

    final opened = await ref.read(mapNavigatorProvider).navigateTo(latitude: latitude, longitude: longitude);
    if (!opened && mounted) {
      _snackBars
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.busNoMapsApp)));
    }
  }

  Future<void> _end(TransportTrip trip) async {
    final waiting = trip.riders.where((r) => r.status == TripRiderStatus.pending).length;
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      title: l10n.busEndTripQuestion,
      message: waiting == 0 ? l10n.busEndAllMarked : l10n.busEndUnmarked(waiting),
      confirmLabel: l10n.busEndTrip,
      cancelLabel: l10n.busKeepGoing,
    );
    if (!confirmed || !mounted) return;

    await _trip.end();
    if (!mounted) return;
    _snackBars
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.busTripEnded)));
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(myTripViewProvider(widget.tripId));
    final notSent = ref.watch(tripMarkQueueProvider.select((queue) => queue.notSentFor(widget.tripId)));

    return ScaffoldMessenger(
      key: _messenger,
      child: AsyncValueView<TripSnapshot>(
        value: view,
        onRetry: () => ref.read(tripDetailProvider(widget.tripId).notifier).refresh(),
        data: (context, snapshot) => _buildTrip(context, snapshot, notSent),
      ),
    );
  }

  Widget _buildTrip(BuildContext context, TripSnapshot snapshot, List<NotSentMark> notSent) {
    final trip = snapshot.trip;
    final running = trip.isInProgress;
    _announceOnce(trip);
    final stops = [...trip.stops]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    final nextStop = running ? stops.where((s) => !s.reached).firstOrNull : null;
    final stopIds = {for (final s in stops) s.id};
    final searching = _query.trim().isNotEmpty;
    final shown = findRiders(trip.riders, _query);
    final unplaced = shown.where((r) => !stopIds.contains(r.stopId)).toList();
    final aboard = trip.riders.where((r) => r.status == TripRiderStatus.boarded).length;

    // Sharing lives as long as this sheet, not as long as the switch's row:
    // the list below builds rows lazily and takes one down once it scrolls
    // out of sight, and the attendant scrolls down to tick children at
    // every stop. Watched here, sharing also carries on under in-app
    // guidance, which is pushed on top of this sheet.
    if (running) ref.watch(locationSharingProvider(trip.id));

    // The search box stays above the list rather than scrolling off with
    // it: the moment it is wanted is the moment the sheet is longest.
    return TripScreenHold(
      active: running,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // SOS and End trip stay put under the thumb, however long the sheet:
        // scrolling to the foot of forty children to find SOS is the wrong
        // moment to be scrolling (docs/mobile-apps-review.md, 1.4).
        bottomNavigationBar: running
            ? _TripActionBar(aboard: aboard, onSos: _trip.raiseSos, onEnd: () => _end(trip), onLate: _late)
            : null,
        body: Column(
          children: [
            if (trip.riders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: RiderSearchField(onChanged: (query) => setState(() => _query = query)),
              ),
            Expanded(
              child: _buildSheet(
                context,
                trip,
                snapshot,
                notSent,
                stops,
                nextStop,
                shown,
                unplaced,
                searching,
                aboard,
                running,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet(
    BuildContext context,
    TransportTrip trip,
    TripSnapshot snapshot,
    List<NotSentMark> notSent,
    List<TripStop> stops,
    TripStop? nextStop,
    List<TripRider> shown,
    List<TripRider> unplaced,
    bool searching,
    int aboard,
    bool running,
  ) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.busMyRoutes),
            ),
            const Spacer(),
            // The spoken next-stop prompts (M7, 3.2), on until muted here.
            if (running) const _VoiceToggle(),
          ],
        ),
        _TripHeader(trip: trip),
        if (snapshot.fromCache)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              isLocalTrip(trip.id) ? l10n.busStartedOnPhoneNoSignal : l10n.busTripFromPhone,
              key: const Key('trip-from-phone'),
              style: TextStyle(color: context.appColors.muted, fontStyle: FontStyle.italic),
            ),
          ),
        if (running) LocationSharingTile(tripId: trip.id),
        if (notSent.isNotEmpty)
          NotSentCard(
            marks: notSent,
            onDismiss: (mark) => ref.read(tripMarkQueueProvider.notifier).dismissNotSent(mark.clientId),
            onRetry: running ? (mark) => ref.read(tripMarkQueueProvider.notifier).retryNotSent(mark.clientId) : null,
          ),
        if (searching && shown.isEmpty)
          Padding(
            key: const Key('rider-search-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              l10n.busSearchNoMatch(_query.trim()),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted),
            ),
          ),
        // While searching, a stop with nobody matching at it is left out
        // altogether - its header would only say where the child is not.
        // On a drop the children board at school before the first stop.
        if (running && !searching && trip.direction == TripDirection.drop) ?_schoolBulk(trip),
        for (final stop in stops)
          if (!searching || shown.any((r) => r.stopId == stop.id)) ...[
            _StopHeader(
              stop: stop,
              direction: trip.direction,
              isNext: stop.id == nextStop?.id,
              onReached: () {
                if (_acceptTap()) _trip.reachStop(stop);
              },
              onNavigate: () => _navigateTo(stop),
            ),
            if (running && !searching) ?_stopBulk(trip, stop),
            for (final rider in shown.where((r) => r.stopId == stop.id)) _riderTile(rider, running),
          ],
        // On a pickup they leave the bus at school, after the last stop.
        if (running && !searching && trip.direction == TripDirection.pickup) ?_schoolBulk(trip),
        if (unplaced.isNotEmpty) ...[
          _SectionTitle(l10n.busOtherRiders),
          for (final rider in unplaced) _riderTile(rider, running),
        ],
      ],
    );
  }

  /// Many children at once (docs/mobile-apps-review.md, 1.1): the sheet
  /// picks who, each is marked as one tap would mark them, and one Undo
  /// takes the lot back while they wait on the phone.
  Future<void> _markMany(List<TripRider> riders, TripRiderStatus to, String where) async {
    final chosen = await showBulkMarkSheet(context, riders: riders, to: to, where: where);
    if (chosen == null || chosen.isEmpty || !mounted) return;

    final marked = <String>[];
    for (final rider in chosen) {
      final clientId = await _trip.markRider(rider, to);
      if (clientId != null) marked.add(clientId);
    }
    if (marked.isEmpty || !mounted) return;

    final l10n = context.l10n;
    final what = switch (to) {
      TripRiderStatus.boarded => l10n.busBulkDoneBoarded(marked.length, where),
      TripRiderStatus.dropped => l10n.busBulkDoneDropped(marked.length, where),
      _ => l10n.busBulkDoneOther(marked.length, to.labelIn(l10n).toLowerCase(), where),
    };
    _snackBars
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('bulk-undo-snackbar'),
          content: Text(what),
          duration: TripMarkQueue.undoWindow,
          action: SnackBarAction(
            key: const Key('bulk-undo'),
            label: l10n.busUndo,
            onPressed: () async {
              var undone = 0;
              for (final clientId in marked) {
                if (await _trip.undoMark(clientId)) undone++;
              }
              if (!mounted) return;
              _snackBars
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text(undone == marked.length ? l10n.busUndoneAll : l10n.busUndonePartly(undone))),
                );
            },
          ),
        ),
      );
  }

  /// The button under a stop: board who waits there on a pickup, drop who
  /// lives there on a drop. Nothing to do there, no button.
  Widget? _stopBulk(TransportTrip trip, TripStop stop) {
    final pickup = trip.direction == TripDirection.pickup;
    final from = pickup ? TripRiderStatus.pending : TripRiderStatus.boarded;
    final to = pickup ? TripRiderStatus.boarded : TripRiderStatus.dropped;
    final riders = trip.riders.where((r) => r.stopId == stop.id && r.status == from).toList();
    if (riders.isEmpty) return null;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: Key('bulk-stop-${stop.id}'),
        onPressed: () => _markMany(riders, to, stop.name),
        icon: Icon(pickup ? Icons.how_to_reg : Icons.home_outlined),
        label: Text(
          to == TripRiderStatus.dropped
              ? context.l10n.busDropAllHere(riders.length)
              : context.l10n.busBoardAllHere(riders.length),
        ),
      ),
    );
  }

  /// The school end of the run: everyone still aboard dropped at school on
  /// a pickup; everyone boarding at school on a drop.
  Widget? _schoolBulk(TransportTrip trip) {
    final pickup = trip.direction == TripDirection.pickup;
    final from = pickup ? TripRiderStatus.boarded : TripRiderStatus.pending;
    final to = pickup ? TripRiderStatus.dropped : TripRiderStatus.boarded;
    final riders = trip.riders.where((r) => r.status == from).toList();
    if (riders.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        key: const Key('bulk-school'),
        onPressed: () => _markMany(riders, to, context.l10n.busSchoolPlace),
        icon: const Icon(Icons.school_outlined),
        label: Text(
          to == TripRiderStatus.dropped
              ? context.l10n.busDropAllAtSchool(riders.length)
              : context.l10n.busBoardAllAtSchool(riders.length),
        ),
      ),
    );
  }

  /// Marks [rider] and offers to take it back while it waits on the phone.
  Future<void> _markRider(TripRider rider, TripRiderStatus status) async {
    final clientId = await _trip.markRider(rider, status);
    if (clientId == null || !mounted) return;

    _snackBars
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('mark-undo-snackbar'),
          content: Text(status.markedIn(context.l10n, rider.name)),
          duration: TripMarkQueue.undoWindow,
          action: SnackBarAction(
            key: const Key('mark-undo'),
            label: context.l10n.busUndo,
            onPressed: () => _undo(rider, clientId),
          ),
        ),
      );
  }

  Future<void> _undo(TripRider rider, String clientId) async {
    final undone = await _trip.undoMark(clientId);
    if (!mounted) return;

    _snackBars
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(undone ? context.l10n.busUndoneOne(rider.name) : context.l10n.busUndoTooLate)),
      );
  }

  Widget _riderTile(TripRider rider, bool running) {
    return RiderTile(
      rider: rider,
      running: running,
      onMark: (status) {
        if (_acceptTap()) _markRider(rider, status);
      },
      onCallParent: () {
        if (_acceptTap()) _callParent(rider);
      },
    );
  }
}

/// The two buttons a running trip always needs within reach.
class _VoiceToggle extends ConsumerWidget {
  const _VoiceToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(tripVoiceOnProvider);

    return IconButton(
      key: const Key('trip-voice'),
      tooltip: on ? context.l10n.busVoiceMute : context.l10n.busVoiceSpeak,
      icon: Icon(on ? Icons.volume_up_outlined : Icons.volume_off_outlined),
      onPressed: () => ref.read(tripVoiceOnProvider.notifier).set(!on),
    );
  }
}

class _TripActionBar extends StatelessWidget {
  const _TripActionBar({required this.aboard, required this.onSos, required this.onEnd, required this.onLate});

  final int aboard;
  final Future<void> Function() onSos;
  final VoidCallback onEnd;
  final VoidCallback onLate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: const Key('trip-action-bar'),
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (aboard > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    context.l10n.busStillOnBoard(aboard),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appColors.muted),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                // 48, Android's smallest comfortable target (M11, 3.4).
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('trip-late'),
                  onPressed: onLate,
                  icon: const Icon(Icons.schedule),
                  label: Text(context.l10n.busRunningLate),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(flex: 3, child: SosButton(onSos: onSos)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ConstrainedBox(
                      // A minimum, not a fixed height: the label grows with large text (M11, 3.4).
                      constraints: const BoxConstraints(minHeight: 56),
                      child: FilledButton.icon(
                        key: const Key('end-trip'),
                        onPressed: aboard > 0 ? null : onEnd,
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        icon: const Icon(Icons.flag),
                        label: Text(context.l10n.busEndTrip),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripHeader extends StatelessWidget {
  const _TripHeader({required this.trip});

  final TransportTrip trip;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final l10n = context.l10n;
    final badge = trip.status.badgeIn(l10n);
    final tone = switch (trip.status) {
      TripStatus.inProgress => BadgeTone.info,
      TripStatus.completed => BadgeTone.success,
      TripStatus.cancelled => BadgeTone.danger,
    };
    int count(TripRiderStatus status) => trip.riders.where((r) => r.status == status).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.routeName} - ${trip.direction.labelIn(l10n)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusBadge(label: badge, tone: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text('${trip.vehicleName} · ${trip.vehicleRegistrationNumber}', style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            Text(
              l10n.busTripCounts(
                count(TripRiderStatus.boarded),
                count(TripRiderStatus.pending),
                count(TripRiderStatus.dropped),
                count(TripRiderStatus.absent),
              ),
              key: const Key('trip-counts'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopHeader extends StatelessWidget {
  const _StopHeader({
    required this.stop,
    required this.direction,
    required this.isNext,
    required this.onReached,
    required this.onNavigate,
  });

  final TripStop stop;
  final TripDirection direction;
  final bool isNext;
  final VoidCallback onReached;
  final VoidCallback onNavigate;

  /// A stop nobody has placed on the map cannot be navigated to, and a
  /// button that does nothing is worse than no button.
  bool get _hasPosition =>
      double.tryParse(stop.latitude ?? '') != null && double.tryParse(stop.longitude ?? '') != null;

  @override
  Widget build(BuildContext context) {
    final time = direction == TripDirection.pickup ? stop.pickupTime : stop.dropTime;

    return Padding(
      key: Key('stop-${stop.id}'),
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Icon(
            stop.reached ? Icons.check_circle : Icons.location_on_outlined,
            color: stop.reached ? context.appColors.success : context.appColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${stop.sequenceNumber}. ${stop.name}${time == null ? '' : ' · $time'}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (isNext && !stop.reached && _hasPosition)
            SizedBox(
              height: 48,
              width: 48,
              child: IconButton(
                key: Key('navigate-stop-${stop.id}'),
                onPressed: onNavigate,
                icon: const Icon(Icons.directions),
                tooltip: context.l10n.busNavigateTo(stop.name),
              ),
            ),
          if (stop.reached)
            StatusBadge(label: context.l10n.busReached, tone: BadgeTone.success)
          else if (isNext)
            ConstrainedBox(
              // A minimum, not a fixed height: the label grows with large text (M11, 3.4).
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.icon(
                key: Key('reach-stop-${stop.id}'),
                onPressed: onReached,
                icon: const Icon(Icons.place),
                label: Text(context.l10n.busReached),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    );
  }
}
