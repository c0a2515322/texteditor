import 'package:flutter_test/flutter_test.dart';
import 'package:texteditor/main.dart';

void main() {
  testWidgets('Text editor smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TextEditorApp());

    // Verify that the text editor page is displayed.
    expect(find.byType(TextEditorPage), findsOneWidget);
  });
}
