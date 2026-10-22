import 'package:flutter/material.dart';

import '../models/borrow_request.dart';
import '../repositories/document_repository.dart';

/// Danh sách người đang có quyền với tài liệu; chủ sở hữu có thể thu hồi.
class ShareManagerDialog extends StatefulWidget {
  const ShareManagerDialog({
    super.key,
    required this.repository,
    required this.documentId,
  });

  final DocumentRepository repository;
  final String documentId;

  @override
  State<ShareManagerDialog> createState() => _ShareManagerDialogState();
}

class _ShareManagerDialogState extends State<ShareManagerDialog> {
  late Future<List<SharedAccess>> _future =
      widget.repository.listShares(widget.documentId);

  Future<void> _revoke(SharedAccess access) async {
    try {
      await widget.repository
          .revokeShare(documentId: widget.documentId, userId: access.userId);
      if (!mounted) return;
      setState(() => _future = widget.repository.listShares(widget.documentId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể thu hồi quyền: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quản lý quyền truy cập'),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<List<SharedAccess>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                snapshot.error.toString().contains('Owner')
                    ? 'Chỉ chủ sở hữu mới quản lý được quyền truy cập.'
                    : 'Không tải được danh sách: ${snapshot.error}',
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const Text('Tài liệu chưa được chia sẻ cho ai.');
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final access in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(access.email ?? access.userId),
                    subtitle: Text([
                      access.permission == 'editor' ? 'Chỉnh sửa' : 'Chỉ xem',
                      if (access.source == 'borrow') 'mượn',
                      if (access.expiresAt != null)
                        'đến ${access.expiresAt!.day}/${access.expiresAt!.month}/${access.expiresAt!.year}',
                    ].join(' • ')),
                    trailing: IconButton(
                      tooltip: 'Thu hồi quyền',
                      icon: const Icon(Icons.person_remove_outlined),
                      color: Colors.red,
                      onPressed: () => _revoke(access),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
