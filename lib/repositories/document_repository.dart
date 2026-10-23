import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/borrow_request.dart';
import '../models/document_struct.dart';

class DocumentRepository {
  DocumentRepository(this._database, {SupabaseClient? client})
      : _client = client;

  final AppDatabase _database;
  final SupabaseClient? _client;
  final Uuid _uuid = const Uuid();
  bool _refreshStarted = false;

  SupabaseClient get _requiredClient {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase chưa được khởi tạo.');
    }

    return client;
  }

  Future<dynamic> _invoke(
    String path, {
    HttpMethod method = HttpMethod.get,
    Map<String, dynamic>? body,
  }) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Người dùng chưa đăng nhập Firebase.');
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Không lấy được Firebase ID token.');
    }
    late final FunctionResponse response;
    try {
      response = await _requiredClient.functions.invoke(
        'documents-api',
        method: method,
        headers: {
          'Authorization': 'Bearer $token',
          'x-firebase-token': token,
          'x-api-path': path,
        },
        body: body,
      );
    } on FunctionException catch (error) {
      throw StateError(
        'documents-api (${error.status}): ${error.details ?? error.reasonPhrase}',
      );
    }
    if (response.status < 200 || response.status >= 300) {
      final message = response.data is Map
          ? response.data['error']?.toString()
          : response.data.toString();
      throw StateError(message ?? 'Cloud request failed.');
    }
    return response.data;
  }

  /// Theo dõi danh sách tài liệu với bộ lọc theo loại, tag và tìm kiếm đa trường
  Stream<List<Document>> watchDocuments({
    String query = '',
    DocumentType? type,
    String? selectedTag,
  }) {
    if (_client != null && !_refreshStarted) {
      _refreshStarted = true;
      refreshFromCloud();
    }
    final statement = _database.select(_database.documents)
      ..orderBy([(document) => OrderingTerm.desc(document.updatedAt)]);
    if (type != null) {
      statement.where((document) => document.type.equals(type.name));
    }
    final normalizedQuery = _normalize(query);
    final normalizedTag = selectedTag != null && selectedTag.isNotEmpty
        ? _normalize(selectedTag)
        : null;

    return statement.watch().map((documents) {
      var result = documents;

      // Lọc theo tag được chọn nếu có
      if (normalizedTag != null && normalizedTag.isNotEmpty) {
        result = result.where((doc) {
          final docTags = parseTags(doc.tags).map(_normalize);
          return docTags.contains(normalizedTag);
        }).toList();
      }

      // Tìm kiếm từ khóa đa trường: tiêu đề, mô tả, tên tệp, tags, địa chỉ
      if (normalizedQuery.isEmpty) return result;

      final words = normalizedQuery.split(' ').where((w) => w.isNotEmpty).toList();
      return result.where((document) {
        final searchableText = _normalize(
          '${document.title} '
          '${document.description ?? ''} '
          '${document.filePath ?? ''} '
          '${document.tags} '
          '${document.physicalAddress ?? ''}',
        );
        return words.every(searchableText.contains);
      }).toList();
    });
  }

  /// Theo dõi tất cả các tags duy nhất hiện có trong cơ sở dữ liệu
  Stream<List<String>> watchAllTags() {
    return _database.select(_database.documents).watch().map((documents) {
      final tagSet = <String>{};
      for (final doc in documents) {
        for (final tag in parseTags(doc.tags)) {
          tagSet.add(tag);
        }
      }
      return tagSet.toList()..sort();
    });
  }

  static String _normalize(String value) {
    const replacements = {
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'đ': 'd',
    };

    final lower = value.trim().toLowerCase();
    final withoutDiacritics = lower.split('').map((character) {
      return replacements[character] ?? character;
    }).join();
    return withoutDiacritics.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> save({
    String? id,
    required String title,
    String? description,
    required DocumentType type,
    String? filePath,
    List<String> tags = const [],
    String? physicalAddress,
    double? latitude,
    double? longitude,
    String? ownerId,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
  }) async {
    final now = DateTime.now();
    final documentId = id ?? _uuid.v4();
    final formattedTags = formatTags(tags);

    if (_client != null) {
      final resolvedOwnerId =
          ownerId ?? firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      if (resolvedOwnerId == null) {
        throw StateError('Người dùng chưa đăng nhập Firebase.');
      }
      await _invoke('/documents', method: HttpMethod.post, body: {
        'id': documentId,
        'title': title.trim(),
        'description': description?.trim(),
        'type': type.name,
        'storage_path': filePath,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'tags': tags,
        'physical_address': physicalAddress?.trim(),
        'latitude': latitude,
        'longitude': longitude,
      });
    }

    await _database.into(_database.documents).insertOnConflictUpdate(
          DocumentsCompanion.insert(
            id: documentId,
            title: title.trim(),
            description: Value(description?.trim()),
            type: type.name,
            filePath: Value(filePath),
            tags: Value(formattedTags),
            physicalAddress: Value(physicalAddress?.trim()),
            latitude: Value(latitude),
            longitude: Value(longitude),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> delete(String id) async {
    if (_client != null) {
      await _invoke('/documents/$id/file', method: HttpMethod.delete);
      await _invoke('/documents/$id', method: HttpMethod.delete);
    }
    await (_database.delete(_database.documents)
          ..where((row) => row.id.equals(id)))
        .go();
  }

  Future<void> refreshFromCloud() async {
    if (_client == null) return;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final rows = await _invoke('/documents') as List<dynamic>;
    final cloudIds = rows.map((row) => row['id'].toString()).toSet();

    for (final row in rows) {
      final createdAt =
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
              DateTime.now();
      final updatedAt =
          DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? createdAt;

      // Xử lý an toàn các trường tags và vị trí từ cloud
      final rawTags = row['tags'];
      final tagsStr = rawTags is List
          ? rawTags.map((e) => e.toString()).join(', ')
          : (rawTags?.toString() ?? '');
      final physicalAddress = row['physical_address']?.toString() ??
          row['physicalAddress']?.toString();
      final lat = row['latitude'] != null ? double.tryParse(row['latitude'].toString()) : null;
      final lng = row['longitude'] != null ? double.tryParse(row['longitude'].toString()) : null;

      await _database.into(_database.documents).insertOnConflictUpdate(
            DocumentsCompanion.insert(
              id: row['id'].toString(),
              title: row['title'].toString(),
              description: Value(row['description'] as String?),
              type: row['type'].toString(),
              filePath: Value(row['storage_path'] as String?),
              tags: Value(tagsStr),
              physicalAddress: Value(physicalAddress),
              latitude: Value(lat),
              longitude: Value(lng),
              createdAt: createdAt,
              updatedAt: updatedAt,
            ),
          );
    }
    final localDocuments = await _database.select(_database.documents).get();
    for (final localDocument in localDocuments) {
      if (!cloudIds.contains(localDocument.id)) {
        await (_database.delete(_database.documents)
              ..where((row) => row.id.equals(localDocument.id)))
            .go();
      }
    }
  }

  Future<void> shareByEmail({
    required String documentId,
    required String email,
    required String permission,
  }) async {
    if (_client == null) {
      throw StateError('Chức năng chia sẻ cần kết nối Supabase.');
    }
    if (permission != 'viewer' && permission != 'editor') {
      throw ArgumentError.value(permission, 'permission');
    }
    await _invoke('/share', method: HttpMethod.post, body: {
      'document_id': documentId,
      'email': email.trim().toLowerCase(),
      'permission': permission,
    });
  }

  Future<List<Map<String, dynamic>>> recommendations() async {
    if (_client == null) return [];
    final rows = await _invoke('/recommendations') as List<dynamic>;
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<List<String>> tagsForDocument(String documentId) async {
    if (_client == null) return [];
    final rows = await _invoke('/documents/$documentId/tags') as List<dynamic>;
    return rows.map((tag) => tag.toString()).toList();
  }

  Future<void> recordInteraction(String documentId, String action) async {
    if (_client == null) return;
    await _invoke('/interactions', method: HttpMethod.post, body: {
      'document_id': documentId,
      'action': action,
    });
  }

  Future<void> registerFcmToken(String token) async {
    if (_client == null) return;
    await _invoke('/fcm-token',
        method: HttpMethod.post, body: {'token': token});
  }

  Future<void> unregisterFcmToken(String token) async {
    if (_client == null) return;
    await _invoke('/fcm-token',
        method: HttpMethod.delete, body: {'token': token});
  }

  // ===== Mục 4: chia sẻ và mượn tài liệu =====

  Future<List<SharedAccess>> listShares(String documentId) async {
    final rows = await _invoke('/share/$documentId') as List<dynamic>;
    return rows
        .map((row) => SharedAccess.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> revokeShare({
    required String documentId,
    required String userId,
  }) async {
    await _invoke('/share/$documentId/$userId', method: HttpMethod.delete);
  }

  Future<List<BorrowableDocument>> listBorrowable() async {
    final rows = await _invoke('/borrowable') as List<dynamic>;
    return rows
        .map((row) =>
            BorrowableDocument.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> requestBorrow({
    required String documentId,
    required DateTime until,
    String? message,
  }) async {
    await _invoke('/borrow', method: HttpMethod.post, body: {
      'document_id': documentId,
      'borrow_until': until.toUtc().toIso8601String(),
      'message': message?.trim().isEmpty ?? true ? null : message!.trim(),
    });
  }

  Future<List<BorrowRequest>> listBorrowRequests({required bool incoming}) async {
    final rows = await _invoke(
      '/borrow?role=${incoming ? 'incoming' : 'outgoing'}',
    ) as List<dynamic>;
    return rows
        .map((row) => BorrowRequest.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// [action] là một trong: approve, reject, return.
  Future<void> decideBorrow(String requestId, String action) async {
    await _invoke('/borrow/$requestId/$action', method: HttpMethod.post);
  }
}
