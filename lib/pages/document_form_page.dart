import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/document_struct.dart';
import '../repositories/document_repository.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

class DocumentFormPage extends StatefulWidget {
  const DocumentFormPage({
    super.key,
    required this.repository,
    this.authService,
    this.storageService,
    this.user,
    this.document,
  });

  final DocumentRepository repository;
  final AuthService? authService;
  final StorageService? storageService;
  final AuthUser? user;
  final Document? document;

  @override
  State<DocumentFormPage> createState() => _DocumentFormPageState();
}

class _DocumentFormPageState extends State<DocumentFormPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();
  bool _tagsLoaded = false;
  final _formKey = GlobalKey<FormState>();
  DocumentType _type = DocumentType.lecture;
  String? _filePath;
  String? _fileName;
  Uint8List? _fileBytes;
  String? _contentType;
  bool _hasNewFile = false;
  bool _isSaving = false;

  bool get _isEditing => widget.document != null;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    if (document != null) {
      widget.repository.tagsForDocument(document.id).then((tags) {
        if (mounted) {
          _tags.text = tags.join(', ');
          _tagsLoaded = true;
        }
      }).catchError((Object _) {});
      _title.text = document.title;
      _description.text = document.description ?? '';
      _type = DocumentTypeCodec.fromValue(document.type);
      _filePath = document.filePath;
      _fileName = document.filePath?.split(RegExp(r'[/\\]')).last;
    } else {
      _tagsLoaded = true;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      final documentId = widget.document?.id ?? const Uuid().v4();
      var storagePath = _filePath;
      if (_hasNewFile &&
          widget.user != null &&
          widget.storageService != null &&
          _fileBytes == null) {
        throw StateError('Không đọc được nội dung tệp để tải lên Firebase.');
      }
      if (_hasNewFile &&
          _fileBytes != null &&
          widget.user != null &&
          widget.storageService != null) {
        storagePath = await widget.storageService!.uploadDocument(
          userId: widget.user!.id,
          documentId: documentId,
          bytes: _fileBytes!,
          fileName: _fileName!,
          contentType: _contentType,
        );
      }
      await widget.repository.save(
        id: documentId,
        title: _title.text,
        description: _description.text,
        type: _type,
        filePath: storagePath,
        ownerId: widget.user?.id,
        fileName: _fileName,
        mimeType: _contentType,
        sizeBytes: _fileBytes?.length,
        tags: !_tagsLoaded
            ? null
            : _tags.text
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể lưu tài liệu: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    const maxFileSize = 10 * 1024 * 1024;
    if (file.size > maxFileSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tệp vượt quá giới hạn 10 MB, vui lòng chọn tệp khác.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final bytes = file.bytes ??
        (file.readStream == null
            ? null
            : Uint8List.fromList(
                (await file.readStream!.expand((chunk) => chunk).toList()),
              ));
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể đọc nội dung tệp đã chọn.')),
      );
      return;
    }

    setState(() {
      _filePath = file.path;
      _fileName = file.name;
      _fileBytes = bytes;
      _contentType = null;
      _hasNewFile = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã chọn tệp: ${file.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Sửa tài liệu' : 'Thêm tài liệu'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              autocorrect: true,
              enableSuggestions: true,
              decoration: const InputDecoration(
                labelText: 'Tiêu đề',
                hintText: 'Nhập tiêu đề bằng tiếng Việt',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Vui lòng nhập tiêu đề'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              autocorrect: true,
              enableSuggestions: true,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                hintText: 'Nhập mô tả bằng tiếng Việt',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                  labelText: 'Thẻ (cách nhau bằng dấu phẩy)',
                  prefixIcon: Icon(Icons.tag)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Loại tài liệu',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: DocumentType.values
                  .map((type) =>
                      DropdownMenuItem(value: type, child: Text(type.label)))
                  .toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_fileName == null ? 'Chọn tệp đính kèm' : _fileName!),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Dung lượng tệp tối đa: 10 MB',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isEditing ? 'Cập nhật tài liệu' : 'Lưu tài liệu'),
            ),
          ],
        ),
      ),
    );
  }
}
