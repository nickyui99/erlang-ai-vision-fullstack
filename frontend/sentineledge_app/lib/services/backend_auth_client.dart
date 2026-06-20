import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendAuthClient {
  BackendAuthClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Uri get _firebaseLoginUri => Uri.parse('$baseUrl/api/v1/auth/firebase/login');

  static String get baseUrl {
    const configured = String.fromEnvironment('SENTINELEDGE_API_BASE_URL');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  Future<BackendUser> loginWithFirebaseIdToken(String idToken) async {
    final response = await _httpClient.post(
      _firebaseLoginUri,
      headers: {'Authorization': 'Bearer $idToken'},
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'] as Map<String, dynamic>?;
      throw BackendAuthException(
        error?['code']?.toString() ?? 'backend_error',
        error?['message']?.toString() ?? 'Backend login failed',
      );
    }

    return BackendUser.fromJson(body['data'] as Map<String, dynamic>);
  }
}

class BackendAuthException implements Exception {
  BackendAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class BackendUser {
  const BackendUser({
    required this.userId,
    required this.email,
    required this.emailVerified,
    required this.role,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String email;
  final bool emailVerified;
  final String role;
  final String? displayName;
  final String? avatarUrl;

  factory BackendUser.fromJson(Map<String, dynamic> json) {
    return BackendUser(
      userId: json['user_id'].toString(),
      email: json['email'].toString(),
      emailVerified: json['email_verified'] == true,
      role: json['role'].toString(),
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }
}
