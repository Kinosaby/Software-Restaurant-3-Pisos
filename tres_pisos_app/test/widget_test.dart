// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tres_pisos_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const TresPisosApp());
    await tester.pumpAndSettle();
    expect(find.text('3 PISOS'), findsOneWidget);
  });
}
