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
import '../widgets/document_map_widget.dart';

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
  String? _selectedTag;
  bool _isBusy = false;

  // Mobile navigation tab: 0 = List, 1 = Map
  int _mobileTabIndex = 0;

  // Selected document for Web/Tablet split-view
  Document? _selectedDocument;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    setState(() => _isBusy = true);
    try {
      await widget.repository.delete(document.id);
      if (_selectedDocument?.id == document.id) {
        setState(() => _selectedDocument = null);
      }
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
    if (storagePath == null ||
        storagePath.trim().isEmpty ||
        storagePath.contains(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(storagePath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tài liệu này chưa có tệp đính kèm trên cloud.')),
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
      if (result == null) return;

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
          const SnackBar(content: Text('Đã cập nhật quyền chia sẻ thành công.')),
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
        content: const Text('Bạn có chắc muốn đăng xuất khỏi tài khoản này không?'),
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

  void _navigateToForm([Document? document]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentFormPage(
          repository: widget.repository,
          authService: widget.authService,
          storageService: StorageService(),
          user: widget.user,
          document: document,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        return isWide ? _buildWebLayout() : _buildMobileLayout();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // LAYOUT CHO MOBILE (Android / iOS)
  // ---------------------------------------------------------------------------
  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài liệu học tập'),
        actions: _buildAppBarActions(),
      ),
      body: _mobileTabIndex == 0
          ? _buildDocumentListSection(isWide: false)
          : _buildFullMapView(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileTabIndex,
        onDestinationSelected: (index) {
          setState(() => _mobileTabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Tài liệu',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Bản đồ vị trí',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        tooltip: 'Thêm tài liệu',
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LAYOUT CHO WEB / TABLET (Màn hình rộng)
  // ---------------------------------------------------------------------------
  Widget _buildWebLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.school, size: 26),
            const SizedBox(width: 10),
            const Text('Hệ thống Quản lý Tài liệu Học tập (TLU)'),
            const Spacer(),
            if (widget.user?.email != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.user!.email!,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: Row(
        children: [
          // NavigationRail bên trái theo quy chuẩn README mục 9
          NavigationRail(
            selectedIndex: _mobileTabIndex,
            onDestinationSelected: (index) {
              setState(() => _mobileTabIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: Color(0xFF00796B)),
            selectedLabelTextStyle: const TextStyle(
              color: Color(0xFF00796B),
              fontWeight: FontWeight.bold,
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.library_books_outlined),
                selectedIcon: Icon(Icons.library_books),
                label: Text('Tài liệu'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: Text('Bản đồ'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),

          // Nội dung chính
          Expanded(
            child: _mobileTabIndex == 1
                ? _buildFullMapView()
                : Row(
                    children: [
                      // Cột trái: Danh sách + bộ lọc
                      SizedBox(
                        width: 440,
                        child: _buildDocumentListSection(isWide: true),
                      ),
                      const VerticalDivider(thickness: 1, width: 1),

                      // Cột phải: Bảng chi tiết tài liệu hoặc bản đồ kết hợp
                      Expanded(
                        child: _buildDetailOrMapPane(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToForm(),
        icon: const Icon(Icons.add),
        label: const Text('Thêm tài liệu mới'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PHẦN DANH SÁCH & BỘ LỌC TÀI LIỆU
  // ---------------------------------------------------------------------------
  Widget _buildDocumentListSection({required bool isWide}) {
    return Column(
      children: [
        // Thanh tìm kiếm và bộ lọc loại
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Tìm kiếm tài liệu...',
                    hintText: 'Theo tiêu đề, mô tả, thẻ, địa chỉ...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<DocumentType?>(
                value: _type,
                hint: const Text('Loại'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tất cả')),
                  ...DocumentType.values.map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _type = value),
              ),
            ],
          ),
        ),

        // Thanh cuộn lọc theo Tag (FilterChip)
        _buildTagFilterBar(),

        // Danh sách tài liệu
        Expanded(
          child: StreamBuilder<List<Document>>(
            stream: widget.repository.watchDocuments(
              query: _searchController.text,
              type: _type,
              selectedTag: _selectedTag,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final documents = snapshot.data ?? [];
              if (documents.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final document = documents[index];
                  final isSelected = _selectedDocument?.id == document.id;

                  return _buildDocumentCard(
                    document: document,
                    isSelected: isSelected,
                    isWide: isWide,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Thanh lọc theo Tag
  Widget _buildTagFilterBar() {
    return StreamBuilder<List<String>>(
      stream: widget.repository.watchAllTags(),
      builder: (context, snapshot) {
        final tags = snapshot.data ?? [];
        if (tags.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('Tất cả thẻ'),
                  selected: _selectedTag == null,
                  onSelected: (_) => setState(() => _selectedTag = null),
                ),
              ),
              ...tags.map((tag) {
                final isSelected = _selectedTag == tag;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    selectedColor: const Color(0xFFB2DFDB),
                    onSelected: (selected) {
                      setState(() {
                        _selectedTag = selected ? tag : null;
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // Card hiển thị thông tin từng tài liệu
  Widget _buildDocumentCard({
    required Document document,
    required bool isSelected,
    required bool isWide,
  }) {
    final tags = parseTags(document.tags);
    final hasLocation = document.latitude != null && document.longitude != null ||
        (document.physicalAddress != null && document.physicalAddress!.isNotEmpty);

    return Card(
      elevation: isSelected ? 3 : 1,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? const Color(0xFF00897B) : const Color(0xFFE0E0E0),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() => _selectedDocument = document);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header card: Icon + Tiêu đề + Type badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getDocumentIcon(document.type),
                      color: const Color(0xFF00796B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF004D40),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x1F009688),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                  DocumentTypeCodec.fromValue(document.type).label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF00695C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (document.filePath != null) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.attachment, size: 14, color: Colors.black54),
                                const Text('Có tệp', style: TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Thẻ phân loại (Tags)
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tags.map((t) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F8E9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFC5E1A5)),
                      ),
                      child: Text(
                        '#$t',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF33691E)),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Vị trí vật lý (nếu có)
              if (hasLocation) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place, size: 14, color: Colors.redAccent),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        document.physicalAddress ?? 'Có tọa độ lưu trữ',
                        style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(height: 16),

              // Các nút thao tác
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Mở tệp',
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: () => _openDocument(document),
                  ),
                  IconButton(
                    tooltip: 'Sửa tài liệu',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: Colors.green[700],
                    onPressed: () => _navigateToForm(document),
                  ),
                  IconButton(
                    tooltip: 'Xóa tài liệu',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.red[700],
                    onPressed: _isBusy ? null : () => _deleteDocument(document),
                  ),
                  IconButton(
                    tooltip: 'Quản lý quyền truy cập',
                    icon: const Icon(Icons.manage_accounts_outlined, size: 20),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => ShareManagerDialog(
                        repository: widget.repository,
                        documentId: document.id,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chia sẻ qua email',
                    icon: const Icon(Icons.share_outlined, size: 20),
                    onPressed: _isBusy ? null : () => _shareDocument(document),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CỘT CHI TIẾT & BẢN ĐỒ (CHO WEB/TABLET)
  // ---------------------------------------------------------------------------
  Widget _buildDetailOrMapPane() {
    final doc = _selectedDocument;

    return StreamBuilder<List<Document>>(
      stream: widget.repository.watchDocuments(),
      builder: (context, snapshot) {
        final allDocuments = snapshot.data ?? [];

        if (doc == null) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chọn một tài liệu để xem chi tiết hoặc khám phá bản đồ vị trí:',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF004D40)),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DocumentMapWidget(
                    documents: allDocuments,
                    selectedDocument: null,
                  ),
                ),
              ],
            ),
          );
        }

        final tags = parseTags(doc.tags);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header chi tiết
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getDocumentIcon(doc.type),
                      size: 32,
                      color: const Color(0xFF00796B),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF004D40),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Loại: ${DocumentTypeCodec.fromValue(doc.type).label}',
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng chi tiết',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selectedDocument = null),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Thẻ phân loại
              if (tags.isNotEmpty) ...[
                const Text('Thẻ phân loại:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags.map((t) => Chip(
                    label: Text(t),
                    backgroundColor: const Color(0xFFE0F2F1),
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Mô tả
              if (doc.description != null && doc.description!.isNotEmpty) ...[
                const Text('Mô tả:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFB2DFDB)),
                  ),
                  child: Text(
                    doc.description!,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Địa chỉ vật lý & Bản đồ
              const Text('Vị trí lưu trữ & Bản đồ:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              if (doc.physicalAddress != null && doc.physicalAddress!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.place, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          doc.physicalAddress!,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(
                height: 260,
                child: DocumentMapWidget(
                  documents: allDocuments,
                  selectedDocument: doc,
                ),
              ),

              const SizedBox(height: 20),

              // Thanh công cụ hành động
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openDocument(doc),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Mở tệp đính kèm'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _navigateToForm(doc),
                    icon: const Icon(Icons.edit),
                    label: const Text('Sửa'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _shareDocument(doc),
                    icon: const Icon(Icons.share),
                    label: const Text('Chia sẻ'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _deleteDocument(doc),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Xóa', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TOÀN BỘ MÀN HÌNH BẢN ĐỒ (CHO TAB MAP)
  // ---------------------------------------------------------------------------
  Widget _buildFullMapView() {
    return StreamBuilder<List<Document>>(
      stream: widget.repository.watchDocuments(),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? [];
        return DocumentMapWidget(
          documents: docs,
          selectedDocument: _selectedDocument,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY STATE & HELPERS
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 56,
                color: Color(0xFF00796B),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có tài liệu nào phù hợp',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hãy thử thay đổi từ khóa tìm kiếm, lọc theo thẻ khác hoặc bấm nút thêm tài liệu mới.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _navigateToForm(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm tài liệu ngay'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget>? _buildAppBarActions() {
    if (widget.authService == null) return null;
    return [
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
          constraints: const BoxConstraints(maxWidth: 160),
          child: Center(
            child: Text(
              widget.user!.email!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      IconButton(
        tooltip: 'Đăng xuất',
        icon: const Icon(Icons.logout),
        onPressed: _confirmSignOut,
      ),
    ];
  }

  IconData _getDocumentIcon(String type) {
    switch (type) {
      case 'lecture':
        return Icons.menu_book_rounded;
      case 'assignment':
        return Icons.assignment_outlined;
      default:
        return Icons.article_outlined;
    }
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
                child: Text('Chỉ xem (Viewer)'),
              ),
              DropdownMenuItem(
                value: 'editor',
                child: Text('Được chỉnh sửa (Editor)'),
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
