import 'dart:async';

import 'package:edutrack_app/features/maps/data/places_repository.dart';

/// Test double for [PlacesRepository] - the server standing in for Google
/// (docs/maps.md, M1).
///
/// Every method answers without a network, and the real one never throws
/// either: searching is a convenience on top of two boxes somebody can
/// always type into, so a failed lookup is an empty answer rather than an
/// error.
class FakePlacesRepository implements PlacesRepository {
  FakePlacesRepository({this.suggestions = const [], this.place, this.address = ''});

  List<PlaceSuggestion> suggestions;

  /// Null is a lookup that failed - the pin must stay where it was.
  FoundPlace? place;

  /// Empty is a real answer: the sea has no address.
  String address;

  /// When set, [search] waits on it, so a test can see the spinner.
  Completer<void>? searchGate;

  int searches = 0;
  int finds = 0;
  int describes = 0;
  String? lastQuery;
  double? lastNearLatitude;
  String? lastPlaceId;

  @override
  Future<List<PlaceSuggestion>> search(String query, {double? nearLatitude, double? nearLongitude}) async {
    searches++;
    lastQuery = query;
    lastNearLatitude = nearLatitude;

    if (searchGate != null) await searchGate!.future;

    return suggestions;
  }

  @override
  Future<FoundPlace?> find(String placeId) async {
    finds++;
    lastPlaceId = placeId;

    return place;
  }

  @override
  Future<String> describe(double latitude, double longitude) async {
    describes++;

    return address;
  }
}
