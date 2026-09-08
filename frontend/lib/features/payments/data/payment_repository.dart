import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/payment.dart';
import 'payment_api.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(paymentApiProvider)),
);

class PaymentRepository {
  PaymentRepository(this._api);

  final PaymentApi _api;

  Future<List<Payment>> list({int? schoolId}) async {
    try {
      final page = await _api.list(schoolId: schoolId);
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
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
    try {
      return await _api.create(
        schoolId: schoolId,
        paymentType: paymentType,
        amount: amount,
        paymentDate: paymentDate,
        paymentMode: paymentMode,
        referenceNumber: referenceNumber,
        notes: notes,
        status: status,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<Payment> updateStatus(int paymentId, PaymentStatus status) async {
    try {
      return await _api.updateStatus(paymentId, status);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaymentSummary> summary() async {
    try {
      return await _api.summary();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
