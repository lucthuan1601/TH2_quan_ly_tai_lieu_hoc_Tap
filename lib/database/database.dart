import 'package:drift/drift.dart';

part 'database.g.dart';

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get type => text()();
  TextColumn get filePath => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get physicalAddress => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Documents])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(documents, documents.tags);
            await m.addColumn(documents, documents.physicalAddress);
            await m.addColumn(documents, documents.latitude);
            await m.addColumn(documents, documents.longitude);
          }
        },
      );
}
