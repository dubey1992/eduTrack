/// Transport analytics, A6 (docs/analytics.md), as `GET /analytics/transport`
/// sends it: each route month by month, and the stops most often late.
library;

class RouteMonth {
  const RouteMonth({
    required this.from,
    required this.workingDays,
    required this.daysRun,
    required this.tripsCompleted,
    required this.tripsCancelled,
    required this.ridersOnList,
    required this.boarded,
    required this.absent,
    required this.boardedRate,
    required this.arrivals,
    required this.late,
    required this.onTimeRate,
    required this.averageMinutesLate,
    required this.averageMinutes,
    required this.longestMinutes,
  });

  factory RouteMonth.fromJson(Map<String, dynamic> json) {
    final service = json['service'] as Map<String, dynamic>;
    final riders = json['riders'] as Map<String, dynamic>;
    final onTime = json['on_time'] as Map<String, dynamic>;
    final length = json['length'] as Map<String, dynamic>;

    return RouteMonth(
      from: json['from'] as String,
      workingDays: service['working_days'] as int,
      daysRun: service['days_run'] as int,
      tripsCompleted: service['trips_completed'] as int,
      tripsCancelled: service['trips_cancelled'] as int,
      ridersOnList: riders['on_list'] as int,
      boarded: riders['boarded'] as int,
      absent: riders['absent'] as int,
      boardedRate: (riders['boarded_rate'] as num?)?.toDouble(),
      arrivals: onTime['arrivals'] as int,
      late: onTime['late'] as int,
      onTimeRate: (onTime['on_time_rate'] as num?)?.toDouble(),
      averageMinutesLate: (onTime['average_minutes_late'] as num?)?.toDouble(),
      averageMinutes: (length['average_minutes'] as num?)?.toDouble(),
      longestMinutes: (length['longest_minutes'] as num?)?.toDouble(),
    );
  }

  final String from;
  final int workingDays;
  final int daysRun;
  final int tripsCompleted;
  final int tripsCancelled;
  final int ridersOnList;
  final int boarded;
  final int absent;
  final double? boardedRate;
  final int arrivals;
  final int late;
  final double? onTimeRate;
  final double? averageMinutesLate;
  final double? averageMinutes;
  final double? longestMinutes;
}

class RouteAnalytics {
  const RouteAnalytics({required this.route, required this.months});

  factory RouteAnalytics.fromJson(Map<String, dynamic> json) {
    return RouteAnalytics(
      route: json['route'] as String,
      months: (json['months'] as List<dynamic>)
          .map((month) => RouteMonth.fromJson(month as Map<String, dynamic>))
          .toList(),
    );
  }

  final String route;
  final List<RouteMonth> months;
}

class LateStop {
  const LateStop({
    required this.stop,
    required this.route,
    required this.arrivals,
    required this.late,
    required this.lateRate,
    required this.averageMinutesLate,
  });

  factory LateStop.fromJson(Map<String, dynamic> json) {
    return LateStop(
      stop: json['stop'] as String? ?? '-',
      route: json['route'] as String? ?? '-',
      arrivals: json['arrivals'] as int,
      late: json['late'] as int,
      lateRate: (json['late_rate'] as num).toDouble(),
      averageMinutesLate: (json['average_minutes_late'] as num).toDouble(),
    );
  }

  final String stop;
  final String route;
  final int arrivals;
  final int late;
  final double lateRate;
  final double averageMinutesLate;
}

class TransportOverview {
  const TransportOverview({required this.lateAfterMinutes, required this.routes, required this.lateStops});

  factory TransportOverview.fromJson(Map<String, dynamic> json) {
    return TransportOverview(
      lateAfterMinutes: json['late_after_minutes'] as int,
      routes: (json['routes'] as List<dynamic>)
          .map((route) => RouteAnalytics.fromJson(route as Map<String, dynamic>))
          .toList(),
      lateStops: (json['late_stops'] as List<dynamic>)
          .map((stop) => LateStop.fromJson(stop as Map<String, dynamic>))
          .toList(),
    );
  }

  /// A bus is late at a stop this many minutes after its scheduled time.
  final int lateAfterMinutes;
  final List<RouteAnalytics> routes;
  final List<LateStop> lateStops;
}
