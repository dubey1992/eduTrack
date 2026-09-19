import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/profile.dart';

final profileApiProvider = Provider<ProfileApi>((ref) => ProfileApi(ref.watch(dioClientProvider)));

class ProfileApi {
  ProfileApi(this._dio);

  final Dio _dio;

  Future<Profile> get() async {
    final response = await _dio.get('/profile');
    return _profile(response);
  }

  /// Sends only the keys in [changes]; an empty mobile or address clears it.
  Future<Profile> update(Map<String, String> changes) async {
    final response = await _dio.patch('/profile', data: changes);
    return _profile(response);
  }

  Future<Profile> changeEmail({required String email, required String currentPassword}) async {
    final response = await _dio.post('/profile/email', data: {'email': email, 'current_password': currentPassword});
    return _profile(response);
  }

  Future<Profile> uploadPhoto({required List<int> bytes, required String fileName}) async {
    final form = FormData.fromMap({'photo': MultipartFile.fromBytes(bytes, filename: fileName)});
    final response = await _dio.post('/profile/photo', data: form);
    return _profile(response);
  }

  Future<Profile> removePhoto() async {
    final response = await _dio.delete('/profile/photo');
    return _profile(response);
  }

  Profile _profile(Response<dynamic> response) => Profile.fromJson(response.data as Map<String, dynamic>);
}
