import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/core/models/scan_flow.dart';
import 'package:instaham/features/capture/presentation/widgets/reference_object_picker.dart';

void main() {
  testWidgets('reference picker returns the selected known length', (
    WidgetTester tester,
  ) async {
    ReferenceSelection? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferenceObjectPicker(
            onSelect: (value) => selected = value,
            onCustom: () {},
            onBack: () {},
          ),
        ),
      ),
    );

    expect(find.text('Choose reference object'), findsOneWidget);
    expect(find.text('Custom reference'), findsOneWidget);

    await tester.tap(find.text('1-meter stick'));
    await tester.pump();

    expect(selected, ReferenceSelection.meterStick);
    expect(selected!.lengthCm, 100);
  });
}
