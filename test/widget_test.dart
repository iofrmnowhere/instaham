import 'package:flutter_test/flutter_test.dart';
import 'package:instaham/app.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    // Verify INSTAHAM title is displayed
    expect(find.text('INSTAHAM'), findsOneWidget);
  });
}
