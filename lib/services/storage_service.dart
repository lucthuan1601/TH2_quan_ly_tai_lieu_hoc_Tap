import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> uploadDocument({
    required String userId,
    required String documentId,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final token = await _firebaseToken();
    final response = await _client.functions.invoke(
      'documents-api',
      method: HttpMethod.post,
      headers: {
        'Authorization': 'Bearer $token',
        'x-firebase-token': token,
        'x-api-path': '/documents/$documentId/file',
      },
      body: {
        'file_name': safeName,
        'mime_type': contentType ?? _contentType(fileName),
        'base64': base64Encode(bytes),
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(response.data.toString());
    }
    final path = (response.data as Map<String, dynamic>)['storage_path'];
    if (path is! String || path.isEmpty) {
      throw StateError('Supabase Storage không trả về đường dẫn file.');
    }
    return path;
  }

  Future<String> createSignedDownloadUrl(String documentId) async {
    final token = await _firebaseToken();
    final response = await Supabase.instance.client.functions.invoke(
      'documents-api',
      method: HttpMethod.get,
      headers: {
        'Authorization': 'Bearer $token',
        'x-firebase-token': token,
        'x-api-path': '/documents/$documentId/file-url',
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(response.data.toString());
    }
    final url = (response.data as Map<String, dynamic>)['url'];
    if (url is! String || url.isEmpty) {
      throw StateError('Signed URL không hợp lệ.');
    }
    return url;
  }

  Future<String> _firebaseToken() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Người dùng chưa đăng nhập Firebase.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Không lấy được Firebase ID token.');
    }
    return token;
  }

  static String _contentType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    const types = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
    };
    return types[extension] ?? 'application/octet-stream';
  }
}
