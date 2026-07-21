import 'package:flutter_test/flutter_test.dart';
import 'package:cuddle_umbrella/main.dart';

void main() {
  testWidgets('App smoke test - verifies title is present', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that our app shows the main title.
    expect(find.text('Cuddle Umbrella'), findsOneWidget);
    expect(find.text('Bağlantıyı Çözümle'), findsOneWidget);
  });
}
