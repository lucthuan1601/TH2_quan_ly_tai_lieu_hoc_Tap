import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/document_struct.dart';
import '../repositories/document_repository.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/document_map_widget.dart';

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
  final _tagInput = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  DocumentType _type = DocumentType.lecture;
  String? _filePath;
  String? _fileName;
  Uint8List? _fileBytes;
  String? _contentType;
  bool _hasNewFile = false;
  bool _isSaving = false;

  // Quản lý nhiều tags
  final List<String> _tags = [];

  // Quản lý vị trí vật lý
  bool _isPhysicalDocument = false;
  double? _currentLat;
  double? _currentLng;

  bool get _isEditing => widget.document != null;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    if (document != null) {
      _title.text = document.title;
      _description.text = document.description ?? '';
      _type = DocumentTypeCodec.fromValue(document.type);
      _filePath = document.filePath;
      _fileName = document.filePath?.split(RegExp(r'[/\\]')).last;

      _tags.addAll(parseTags(document.tags));
      widget.repository.tagsForDocument(document.id).then((tags) {
        if (!mounted || tags.isEmpty) return;
        setState(() {
          _tags
            ..clear()
            ..addAll(tags);
        });
      }).catchError((Object _) {});

      if (document.physicalAddress != null && document.physicalAddress!.isNotEmpty ||
          document.latitude != null ||
          document.longitude != null) {
        _isPhysicalDocument = true;
        _address.text = document.physicalAddress ?? '';
        _currentLat = document.latitude;
        _currentLng = document.longitude;
        if (document.latitude != null) _latitude.text = document.latitude!.toString();
        if (document.longitude != null) _longitude.text = document.longitude!.toString();
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _tagInput.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _addTag(String rawTag) {
    final clean = rawTag.trim();
    if (clean.isEmpty) return;
    if (!_tags.contains(clean)) {
      setState(() {
        _tags.add(clean);
      });
    }
    _tagInput.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  void _onLocationPicked(double lat, double lng, String addr) {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      _latitude.text = lat.toStringAsFixed(6);
      _longitude.text = lng.toStringAsFixed(6);
      _address.text = addr;
    });
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
        throw StateError('Không đọc được nội dung tệp để tải lên Supabase.');
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

      final lat = _isPhysicalDocument ? double.tryParse(_latitude.text.trim()) : null;
      final lng = _isPhysicalDocument ? double.tryParse(_longitude.text.trim()) : null;
      final addr = _isPhysicalDocument ? _address.text.trim() : null;

      await widget.repository.save(
        id: documentId,
        title: _title.text,
        description: _description.text,
        type: _type,
        filePath: storagePath,
        tags: _tags,
        physicalAddress: addr,
        latitude: lat,
        longitude: lng,
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                // Phần 1: Thông tin cơ bản
                _buildSectionHeader(Icons.info_outline, 'Thông tin cơ bản'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề tài liệu *',
                    hintText: 'VD: Giáo trình Giải tích 1',
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
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả chi tiết',
                    hintText: 'Tóm tắt nội dung, giảng viên, môn học...',
                    prefixIcon: Icon(Icons.notes),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DocumentType>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Loại tài liệu',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: DocumentType.values
                      .map((type) =>
                          DropdownMenuItem(value: type, child: Text(type.label)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),

                const SizedBox(height: 28),

                // Phần 2: Quản lý nhiều Tag
                _buildSectionHeader(Icons.local_offer_outlined, 'Thẻ phân loại (Tags)'),
                const SizedBox(height: 8),
                const Text(
                  'Gắn nhiều thẻ giúp tìm kiếm, lọc nhanh và tối ưu hóa gợi ý tài liệu học tập.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagInput,
                        decoration: const InputDecoration(
                          labelText: 'Nhập tên thẻ',
                          hintText: 'VD: Toán cao cấp, CNTT...',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _addTag(_tagInput.text),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm thẻ'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Danh sách tag đã chọn
                if (_tags.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _tags.map((tag) {
                      return Chip(
                        label: Text(tag, style: const TextStyle(fontWeight: FontWeight.w500)),
                        backgroundColor: const Color(0xFFE0F2F1),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _removeTag(tag),
                        side: const BorderSide(color: Color(0xFF80CBC4)),
                      );
                    }).toList(),
                  )
                else
                  const Text('Chưa có thẻ nào được thêm.',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black45, fontSize: 13)),

                const SizedBox(height: 12),
                // Gợi ý tag phổ biến
                const Text('Thẻ gợi ý phổ biến:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00695C))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: defaultSuggestedTags.map((suggested) {
                    final isAdded = _tags.contains(suggested);
                    return ActionChip(
                      label: Text(
                        suggested,
                        style: TextStyle(
                          fontSize: 11,
                          color: isAdded ? Colors.grey : const Color(0xFF00796B),
                        ),
                      ),
                      backgroundColor: isAdded ? Colors.grey[200] : Colors.white,
                      onPressed: isAdded ? null : () => _addTag(suggested),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 28),

                // Phần 3: Tệp đính kèm trên Cloud
                _buildSectionHeader(Icons.cloud_upload_outlined, 'Tệp số hóa trên Cloud'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_fileName == null ? 'Chọn tệp đính kèm (PDF, DOCX, ...)' : _fileName!),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Dung lượng tệp tối đa: 10 MB. Tệp sẽ được lưu an toàn trên Supabase Storage riêng tư.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 28),

                // Phần 4: Vị trí & Lưu trữ vật lý
                _buildSectionHeader(Icons.location_on_outlined, 'Địa chỉ & Vị trí vật lý (Bản đồ)'),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tài liệu có bản cứng / lưu trữ thực tế',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Bật để quản lý địa chỉ lưu trữ, tọa độ và vị trí trên bản đồ.'),
                  value: _isPhysicalDocument,
                  activeThumbColor: const Color(0xFF00897B),
                  onChanged: (val) {
                    setState(() {
                      _isPhysicalDocument = val;
                      if (val && _address.text.isEmpty) {
                        _address.text = tluPresetLocations.first.address;
                        _currentLat = tluPresetLocations.first.latitude;
                        _currentLng = tluPresetLocations.first.longitude;
                        _latitude.text = _currentLat!.toString();
                        _longitude.text = _currentLng!.toString();
                      }
                    });
                  },
                ),

                if (_isPhysicalDocument) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ lưu trữ vật lý',
                      hintText: 'VD: Kệ A3, Phòng 301 Tòa A1, ĐH Thủy Lợi',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitude,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Vĩ độ (Latitude)',
                            prefixIcon: Icon(Icons.explore_outlined),
                          ),
                          onChanged: (val) {
                            final lat = double.tryParse(val);
                            if (lat != null) setState(() => _currentLat = lat);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _longitude,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Kinh độ (Longitude)',
                            prefixIcon: Icon(Icons.explore_outlined),
                          ),
                          onChanged: (val) {
                            final lng = double.tryParse(val);
                            if (lng != null) setState(() => _currentLng = lng);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Widget bản đồ tương tác để chọn vị trí
                  DocumentMapWidget(
                    key: ValueKey('map_picker_${_currentLat}_$_currentLng'),
                    height: 250,
                    isPicker: true,
                    initialLatitude: _currentLat,
                    initialLongitude: _currentLng,
                    initialAddress: _address.text,
                    onLocationChanged: _onLocationPicked,
                  ),
                ],

                const SizedBox(height: 36),

                // Nút Lưu/Cập nhật
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _isSaving
                        ? 'Đang lưu tài liệu...'
                        : (_isEditing ? 'Cập nhật tài liệu' : 'Lưu tài liệu'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF00796B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
<<<<<<< HEAD
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
=======
          ),
>>>>>>> origin/main
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00695C), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
      ],
    );
  }
}
