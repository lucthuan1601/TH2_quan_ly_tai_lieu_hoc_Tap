import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database.dart';
import '../models/document_struct.dart';
import '../repositories/document_repository.dart';
import 'borrow_page.dart';
import 'document_form_page.dart';
import 'share_manager_dialog.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

class DocumentListPage extends StatefulWidget {
  const DocumentListPage({
    super.key,
    required this.repository,
    this.authService,
    this.user,
  });

  final DocumentRepository repository;
  final AuthService? authService;
  final AuthUser? user;

  @override
  State<DocumentListPage> createState() => _DocumentListPageState();
}

class _DocumentListPageState extends State<DocumentListPage> {
  final _searchController = TextEditingController();
  DocumentType? _type;
  bool _isBusy = false;

  Future<void> _deleteDocument(Document document) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa tài liệu'),
        content: Text('Bạn có chắc muốn xóa "${document.title}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    setState(() => _isBusy = true);
    try {
      await widget.repository.delete(document.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể xóa tài liệu: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openDocument(Document document) async {
    final storagePath = document.filePath;
    // Supabase Storage paths are returned as "<ownerId>/<documentId>/<file>".
    // They do not use the old Firebase "users/" prefix.
    if (storagePath == null ||
        storagePath.trim().isEmpty ||
        storagePath.contains(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(storagePath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tài liệu này chưa có tệp trên cloud.')),
      );
      return;
    }

    try {
      final url = await StorageService().createSignedDownloadUrl(document.id);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        throw StateError('Không thể mở liên kết tài liệu.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể mở tài liệu: $error')),
        );
      }
    }
  }

  Future<void> _shareDocument(Document document) async {
    try {
      final result = await showDialog<_ShareDialogResult>(
        context: context,
        builder: (_) => const _ShareDialog(),
      );
      if (result == null) {
        return;
      }
      final email = result.email.trim();
      final selectedPermission = result.permission;
      final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailPattern.hasMatch(email)) {
        throw const FormatException('Email người nhận không hợp lệ.');
      }

      await widget.repository.shareByEmail(
        documentId: document.id,
        email: email,
        permission: selectedPermission,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật quyền chia sẻ.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chia sẻ tài liệu: $error')),
        );
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content:
            const Text('Bạn có chắc muốn đăng xuất khỏi tài khoản này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (shouldSignOut == true && widget.authService != null) {
      await widget.authService!.signOut();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài liệu học tập'),
        actions: widget.authService == null
            ? null
            : [
                IconButton(
                  tooltip: 'Mượn tài liệu',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BorrowPage(repository: widget.repository),
                    ),
                  ),
                ),
                if (widget.user?.email != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          widget.user!.email!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Đăng xuất',
                  icon: const Icon(Icons.logout),
                  onPressed: _confirmSignOut,
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Tìm kiếm',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<DocumentType?>(
                value: _type,
                hint: const Text('Loại'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tất cả')),
                  ...DocumentType.values.map((type) =>
                      DropdownMenuItem(value: type, child: Text(type.label))),
                ],
                onChanged: (value) => setState(() => _type = value),
              ),
            ]),
          ),
          Expanded(
            child: StreamBuilder(
              stream: widget.repository.watchDocuments(
                query: _searchController.text,
                type: _type,
              ),
              builder: (context, snapshot) {
                final documents = snapshot.data ?? [];
                if (documents.isEmpty) {
                  return const Center(child: Text('Chưa có tài liệu'));
                }
                return ListView.builder(
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(document.title),
                      subtitle: Text(
                        '${DocumentTypeCodec.fromValue(document.type).label}'
                        '${document.filePath == null ? '' : ' • Có tệp đính kèm'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Mở tài liệu',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => _openDocument(document),
                          ),
                          IconButton(
                            tooltip: 'Sửa tài liệu',
                            icon: const Icon(Icons.edit_outlined),
                            color: Colors.green,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DocumentFormPage(
                                  repository: widget.repository,
                                  authService: widget.authService,
                                  storageService: StorageService(),
                                  user: widget.user,
                                  document: document,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Xóa tài liệu',
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.red,
                            onPressed: _isBusy
                                ? null
                                : () => _deleteDocument(document),
                          ),
                          IconButton(
                            tooltip: 'Quản lý quyền truy cập',
                            icon: const Icon(Icons.manage_accounts_outlined),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => ShareManagerDialog(
                                repository: widget.repository,
                                documentId: document.id,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Chia sẻ tài liệu',
                            icon: const Icon(Icons.share_outlined),
                            onPressed:
                                _isBusy ? null : () => _shareDocument(document),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DocumentFormPage(
            repository: widget.repository,
            authService: widget.authService,
            storageService: StorageService(),
            user: widget.user,
          ),
        )),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ShareDialogResult {
  const _ShareDialogResult({
    required this.email,
    required this.permission,
  });

  final String email;
  final String permission;
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog();

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _emailController = TextEditingController();
  String _permission = 'viewer';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chia sẻ tài liệu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email người nhận',
              hintText: 'nguoi-dung@example.com',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _permission,
            decoration: const InputDecoration(labelText: 'Quyền'),
            items: const [
              DropdownMenuItem(
                value: 'viewer',
                child: Text('Chỉ xem'),
              ),
              DropdownMenuItem(
                value: 'editor',
                child: Text('Được chỉnh sửa'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _permission = value);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ShareDialogResult(
              email: _emailController.text,
              permission: _permission,
            ),
          ),
          child: const Text('Chia sẻ'),
        ),
      ],
    );
  }
}
