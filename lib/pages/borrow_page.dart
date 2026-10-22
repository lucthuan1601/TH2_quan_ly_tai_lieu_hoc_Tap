import 'package:flutter/material.dart';

import '../models/borrow_request.dart';
import '../repositories/document_repository.dart';

/// Mục 4: mượn tài liệu — gửi yêu cầu, phê duyệt/từ chối, trả tài liệu.
class BorrowPage extends StatelessWidget {
  const BorrowPage({super.key, required this.repository});

  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mượn tài liệu'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Có thể mượn'),
              Tab(text: 'Đã gửi'),
              Tab(text: 'Nhận được'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BorrowableTab(repository: repository),
            _RequestsTab(repository: repository, incoming: false),
            _RequestsTab(repository: repository, incoming: true),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Tải dữ liệu bất đồng bộ, có loading / rỗng / lỗi và kéo để làm mới.
class _AsyncList<T> extends StatefulWidget {
  const _AsyncList({
    required this.load,
    required this.emptyText,
    required this.itemBuilder,
  });

  final Future<List<T>> Function() load;
  final String emptyText;
  final Widget Function(BuildContext, T, Future<void> Function() reload)
      itemBuilder;

  @override
  State<_AsyncList<T>> createState() => _AsyncListState<T>();
}

class _AsyncListState<T> extends State<_AsyncList<T>> {
  late Future<List<T>> _future = widget.load();

  Future<void> _reload() async {
    setState(() => _future = widget.load());
    await _future.catchError((_) => <T>[]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Không tải được dữ liệu: ${snapshot.error}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Thử lại')),
                ],
              ),
            ),
          );
        }
        final items = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: _reload,
          child: items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text(widget.emptyText)),
                ])
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      widget.itemBuilder(context, items[index], _reload),
                ),
        );
      },
    );
  }
}

class _BorrowableTab extends StatelessWidget {
  const _BorrowableTab({required this.repository});

  final DocumentRepository repository;

  Future<void> _request(
    BuildContext context,
    BorrowableDocument document,
    Future<void> Function() reload,
  ) async {
    final result = await showDialog<_BorrowForm>(
      context: context,
      builder: (_) => _BorrowDialog(title: document.title),
    );
    if (result == null) return;
    try {
      await repository.requestBorrow(
        documentId: document.id,
        until: result.until,
        message: result.message,
      );
      if (context.mounted) _toast(context, 'Đã gửi yêu cầu mượn.');
      await reload();
    } catch (error) {
      if (context.mounted) _toast(context, 'Không thể gửi yêu cầu: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList<BorrowableDocument>(
      load: repository.listBorrowable,
      emptyText: 'Chưa có tài liệu nào để mượn',
      itemBuilder: (context, document, reload) => ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(document.title),
        subtitle: Text('Chủ sở hữu: ${document.ownerEmail ?? 'không rõ'}'),
        trailing: document.pending
            ? const Chip(label: Text('Đã gửi yêu cầu'))
            : FilledButton(
                onPressed: () => _request(context, document, reload),
                child: const Text('Mượn'),
              ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.repository, required this.incoming});

  final DocumentRepository repository;
  final bool incoming;

  Future<void> _decide(
    BuildContext context,
    BorrowRequest request,
    String action,
    String success,
    Future<void> Function() reload,
  ) async {
    try {
      await repository.decideBorrow(request.id, action);
      if (context.mounted) _toast(context, success);
      await reload();
    } catch (error) {
      if (context.mounted) _toast(context, 'Thao tác thất bại: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AsyncList<BorrowRequest>(
      load: () => repository.listBorrowRequests(incoming: incoming),
      emptyText: incoming ? 'Chưa có yêu cầu nào gửi đến bạn' : 'Bạn chưa gửi yêu cầu nào',
      itemBuilder: (context, request, reload) {
        final who = incoming
            ? 'Người mượn: ${request.requesterEmail ?? 'không rõ'}'
            : 'Chủ sở hữu: ${request.ownerEmail ?? 'không rõ'}';
        final actions = <Widget>[];
        if (incoming && request.status == BorrowStatus.pending) {
          actions.addAll([
            TextButton(
              onPressed: () => _decide(
                  context, request, 'reject', 'Đã từ chối yêu cầu.', reload),
              child: const Text('Từ chối'),
            ),
            FilledButton(
              onPressed: () => _decide(
                  context, request, 'approve', 'Đã phê duyệt yêu cầu.', reload),
              child: const Text('Duyệt'),
            ),
          ]);
        } else if (request.status == BorrowStatus.approved) {
          actions.add(OutlinedButton(
            onPressed: () => _decide(context, request, 'return',
                incoming ? 'Đã thu hồi quyền.' : 'Đã trả tài liệu.', reload),
            child: Text(incoming ? 'Thu hồi' : 'Trả tài liệu'),
          ));
        }
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(request.documentTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Chip(label: Text(request.status.label)),
                ]),
                Text(who),
                Text('Mượn đến: ${_formatDate(request.borrowUntil)}'),
                if (request.message != null && request.message!.isNotEmpty)
                  Text('Lời nhắn: ${request.message}'),
                if (actions.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(spacing: 8, children: actions),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BorrowForm {
  const _BorrowForm(this.until, this.message);
  final DateTime until;
  final String message;
}

class _BorrowDialog extends StatefulWidget {
  const _BorrowDialog({required this.title});
  final String title;

  @override
  State<_BorrowDialog> createState() => _BorrowDialogState();
}

class _BorrowDialogState extends State<_BorrowDialog> {
  final _message = TextEditingController();
  DateTime _until = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _until,
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _until = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mượn "${widget.title}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mượn đến ngày'),
            subtitle: Text(_formatDate(_until)),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          TextField(
            controller: _message,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Lời nhắn (tuỳ chọn)'),
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
            // Hết ngày được chọn (23:59) để tránh hết hạn sớm.
            _BorrowForm(
              DateTime(_until.year, _until.month, _until.day, 23, 59),
              _message.text,
            ),
          ),
          child: const Text('Gửi yêu cầu'),
        ),
      ],
    );
  }
}
