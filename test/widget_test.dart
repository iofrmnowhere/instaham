import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/database/app_database.dart';
import 'package:instaham/core/database/database_scope.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/capture/presentation/widgets/reference_object_picker.dart';

void main() {
  testWidgets('reference picker returns the selected known length', (
    WidgetTester tester,
  ) async {
    ReferenceSelection? selected;
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      DatabaseScope(
        database: database,
        child: MaterialApp(
          home: Scaffold(
            body: ReferenceObjectPicker(
              onSelect: (value) => selected = value,
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Choose reference object'), findsOneWidget);
    expect(find.text('Add reference object'), findsOneWidget);

    await tester.tap(find.text('1-meter stick'));
    await tester.pump();

    expect(selected, ReferenceSelection.meterStick);
    expect(selected!.lengthCm, 100);

    await tester.pumpWidget(const SizedBox());
  });
}
