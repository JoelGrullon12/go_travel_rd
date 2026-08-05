import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_travel_rd/widgets/search_box.dart';

void main() {
  testWidgets('los campos de solo lectura disparan onOriginTap/onDestinationTap',
      (tester) async {
    bool originTapped = false;
    bool destinationTapped = false;
    final TextEditingController origin = TextEditingController();
    final TextEditingController destination = TextEditingController();
    addTearDown(origin.dispose);
    addTearDown(destination.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchBox(
            originController: origin,
            destinationController: destination,
            onOriginSubmitted: (_) {},
            onDestinationSubmitted: (_) {},
            readOnly: true,
            onOriginTap: () => originTapped = true,
            onDestinationTap: () => destinationTapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(originTapped, isTrue);
    expect(destinationTapped, isFalse);

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(destinationTapped, isTrue);
  });
}
