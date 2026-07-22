import 'package:flutter_test/flutter_test.dart';

import 'package:rushuu_wifi_home_heatmap/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WifiHeatmapApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
