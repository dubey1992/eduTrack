import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/payment.dart';

final paymentApiProvider = Provider<PaymentApi>((ref) => PaymentApi(ref.watch(dioClientProvider)));

class PaymentApi {
  PaymentApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Payment>> list({int? schoolId}) async {
    final response = await _dio.get('/payments', queryParameters: {'school_id': ?schoolId});
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Payment.fromJson);
  }

  Future<Payment> create({
    required int schoolId,
    required PaymentType paymentType,
    required double amount,
    required DateTime paymentDate,
    required PaymentMode paymentMode,
    String? referenceNumber,
    String? notes,
    required PaymentStatus status,
  }) async {
    final response = await _dio.post(
      '/payments',
      data: {
        'school_id': schoolId,
        'payment_type': paymentType.apiValue,
        'amount': amount.toStringAsFixed(2),
        'payment_date': DateFormat('yyyy-MM-dd').format(paymentDate),
        'payment_mode': paymentMode.apiValue,
        'reference_number': referenceNumber,
        'notes': notes,
        'status': status.apiValue,
      },
    );

    return Payment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Payment> updateStatus(int paymentId, PaymentStatus status) async {
    final response = await _dio.patch('/payments/$paymentId', data: {'status': status.apiValue});
    return Payment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaymentSummary> summary() async {
    final response = await _dio.get('/payments/summary');
    return PaymentSummary.fromJson(response.data as Map<String, dynamic>);
  }
}
