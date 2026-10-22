enum BorrowStatus {
  pending('Chờ duyệt'),
  approved('Đã duyệt'),
  rejected('Đã từ chối'),
  returned('Đã trả'),
  expired('Hết hạn');

  const BorrowStatus(this.label);
  final String label;

  static BorrowStatus fromValue(String? value) => BorrowStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => BorrowStatus.pending,
      );
}

class BorrowRequest {
  const BorrowRequest({
    required this.id,
    required this.documentId,
    required this.documentTitle,
    required this.status,
    required this.borrowUntil,
    this.requesterEmail,
    this.ownerEmail,
    this.message,
  });

  final String id;
  final String documentId;
  final String documentTitle;
  final BorrowStatus status;
  final DateTime borrowUntil;
  final String? requesterEmail;
  final String? ownerEmail;
  final String? message;

  factory BorrowRequest.fromJson(Map<String, dynamic> json) => BorrowRequest(
        id: json['id'].toString(),
        documentId: json['document_id'].toString(),
        documentTitle: json['document_title']?.toString() ?? '',
        status: BorrowStatus.fromValue(json['status']?.toString()),
        borrowUntil: DateTime.parse(json['borrow_until'].toString()).toLocal(),
        requesterEmail: json['requester_email'] as String?,
        ownerEmail: json['owner_email'] as String?,
        message: json['message'] as String?,
      );
}

/// Tài liệu của người khác mà mình có thể gửi yêu cầu mượn.
class BorrowableDocument {
  const BorrowableDocument({
    required this.id,
    required this.title,
    required this.ownerEmail,
    required this.pending,
  });

  final String id;
  final String title;
  final String? ownerEmail;
  final bool pending;

  factory BorrowableDocument.fromJson(Map<String, dynamic> json) =>
      BorrowableDocument(
        id: json['id'].toString(),
        title: json['title'].toString(),
        ownerEmail: json['owner_email'] as String?,
        pending: json['pending'] == true,
      );
}

/// Một người đang có quyền truy cập tài liệu (để chủ sở hữu thu hồi).
class SharedAccess {
  const SharedAccess({
    required this.userId,
    required this.email,
    required this.permission,
    required this.source,
    this.expiresAt,
  });

  final String userId;
  final String? email;
  final String permission;
  final String source;
  final DateTime? expiresAt;

  factory SharedAccess.fromJson(Map<String, dynamic> json) => SharedAccess(
        userId: json['user_id'].toString(),
        email: json['email'] as String?,
        permission: json['permission'].toString(),
        source: json['source']?.toString() ?? 'share',
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'].toString()).toLocal(),
      );
}
