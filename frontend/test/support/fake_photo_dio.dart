import 'package:dio/dio.dart';

/// A Dio that never touches the network, for widgets that fetch a profile
/// photo through dioClientProvider. With [bytes] every request answers them;
/// without, every request fails the way a missing photo does (404).
Dio fakePhotoDio({List<int>? bytes}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'));

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (bytes != null) {
          handler.resolve(Response<List<int>>(requestOptions: options, statusCode: 200, data: bytes));
          return;
        }
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: options, statusCode: 404),
          ),
        );
      },
    ),
  );

  return dio;
}
