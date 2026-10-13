import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quan_ly_tai_lieu_hoc_tap/database/database.dart';
import 'package:quan_ly_tai_lieu_hoc_tap/pages/document_list_page.dart';
import 'package:quan_ly_tai_lieu_hoc_tap/repositories/document_repository.dart';

void main() {
  testWidgets('displays an empty document list', (WidgetTester tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentListPage(repository: DocumentRepository(database)),
      ),
    );
    await tester.pump();

    expect(find.text('Tài liệu học tập'), findsOneWidget);
    expect(find.text('Chưa có tài liệu'), findsOneWidget);

    // Allow Drift's query stream to finish its asynchronous cancellation
    // before the test database is closed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
