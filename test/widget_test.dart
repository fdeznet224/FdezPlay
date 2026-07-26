import 'package:flutter_test/flutter_test.dart';
import 'package:fdezplay/app/app.dart';

void main() {
  testWidgets('FdezPlay inicia correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const FdezPlayApp());

    expect(find.text('FdezPlay'), findsOneWidget);
    expect(find.text('TV • Películas • Series'), findsOneWidget);
  });
}