import 'package:dio/dio.dart';

/// Tries a read again when the server turned it away for a moment.
///
/// The live API runs on shared hosting as CGI - a fresh process for every
/// request (docs/deployment.md). When a screen sends a burst of requests,
/// the host can refuse some of them with its own error page. That page
/// carries no CORS headers, so a browser reports it as "could not reach the
/// server" even though the next try a second later works (2026-11-18).
///
/// Only GET is retried: a read can safely be asked twice, a payment or any
/// other write never can. Only failures that say nothing about the request
/// itself are retried - a lost connection, or a 500/502/504 that is not the
/// API's own JSON error. A 503 means maintenance and is left to the
/// maintenance screen; every 4xx is an answer, not a blip.
class TransientRetryInterceptor extends Interceptor {
  TransientRetryInterceptor(this._dio, {this.delays = const [Duration(seconds: 1), Duration(seconds: 3)]});

  final Dio _dio;

  /// How long to wait before each further try; its length is how many.
  final List<Duration> delays;

  static const _attemptKey = 'transientRetryAttempt';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final attempt = options.extra[_attemptKey] as int? ?? 0;

    if (!isTransient(err) || attempt >= delays.length) {
      handler.next(err);
      return;
    }

    await Future<void>.delayed(delays[attempt]);
    options.extra[_attemptKey] = attempt + 1;

    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Whether [err] is worth one more try.
  static bool isTransient(DioException err) {
    if (err.requestOptions.method.toUpperCase() != 'GET') return false;
    if (err.requestOptions.cancelToken?.isCancelled ?? false) return false;

    if (err.type == DioExceptionType.connectionError) return true;

    final status = err.response?.statusCode;
    if (status != 500 && status != 502 && status != 504) return false;

    // The API's own error is a decision about this request; the host's
    // HTML page is not.
    final data = err.response?.data;
    return !(data is Map && data['code'] is String);
  }
}
