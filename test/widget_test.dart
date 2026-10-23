import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quan_ly_tai_lieu_hoc_tap/database/database.dart';
import 'package:quan_ly_tai_lieu_hoc_tap/models/document_struct.dart';
import 'package:quan_ly_tai_lieu_hoc_tap/pages/document_list_page.dart';
import 'package:quan_ly_tai_lieu_hoc_tap/repositories/document_repository.dart';

void main() {
  group('DocumentListPage & Repository Tests', () {
    testWidgets('displays empty state and responsive navigation on mobile',
        (WidgetTester tester) async {
      // Set mobile screen size
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DocumentRepository(database);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentListPage(repository: repo),
        ),
      );
      await tester.pump();

      // Check Mobile AppBar and Empty state
      expect(find.text('Tài liệu học tập'), findsOneWidget);
      expect(find.text('Chưa có tài liệu nào phù hợp'), findsOneWidget);

      // Check BottomNavigationBar items
      expect(find.text('Tài liệu'), findsOneWidget);
      expect(find.text('Bản đồ vị trí'), findsOneWidget);
      expect(find.text('Mượn tài liệu'), findsOneWidget);

      // Allow Drift's query stream to finish
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('displays responsive split-view on web/tablet screen',
        (WidgetTester tester) async {
      // Set wide screen size (Web/Desktop)
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DocumentRepository(database);

      await tester.pumpWidget(
        MaterialApp(
          home: DocumentListPage(repository: repo),
        ),
      );
      await tester.pump();

      // Check Web Title and NavigationRail
      expect(find.text('Hệ thống Quản lý Tài liệu Học tập (TLU)'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    test('DocumentRepository saves and filters by multi-tags and location',
        () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DocumentRepository(database);

      // Save document with tags and location
      await repo.save(
        id: 'doc-1',
        title: 'Giáo trình Giải tích 1',
        description: 'Tài liệu toán đại cương',
        type: DocumentType.lecture,
        tags: ['Toán', 'Giải tích', 'Đại cương'],
        physicalAddress: 'Thư viện A2 TLU',
        latitude: 21.0074,
        longitude: 105.8248,
      );

      await repo.save(
        id: 'doc-2',
        title: 'Bài tập Lập trình Flutter',
        description: 'Thực hành phát triển ứng dụng di động',
        type: DocumentType.assignment,
        tags: ['CNTT', 'Lập trình Flutter'],
        physicalAddress: 'Phòng 301 Tòa A1',
        latitude: 21.0076,
        longitude: 105.8252,
      );

      // Verify watchAllTags
      final allTags = await repo.watchAllTags().first;
      expect(allTags, containsAll(['CNTT', 'Giải tích', 'Lập trình Flutter', 'Toán', 'Đại cương']));

      // Filter by tag 'CNTT'
      final cnttDocs = await repo.watchDocuments(selectedTag: 'CNTT').first;
      expect(cnttDocs.length, equals(1));
      expect(cnttDocs.first.title, equals('Bài tập Lập trình Flutter'));

      // Search by keyword across tag
      final mathDocs = await repo.watchDocuments(query: 'giai tich').first;
      expect(mathDocs.length, equals(1));
      expect(mathDocs.first.title, equals('Giáo trình Giải tích 1'));

      // Search by location address
      final libraryDocs = await repo.watchDocuments(query: 'thu vien a2').first;
      expect(libraryDocs.length, equals(1));
      expect(libraryDocs.first.id, equals('doc-1'));
    });
  });
}
