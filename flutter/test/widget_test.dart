import 'package:flutter_test/flutter_test.dart';
import 'package:geo_face/main.dart';

void main() {
  testWidgets('Dashboard renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the dashboard title and options are present.
    expect(find.text('Attendance Portal'), findsOneWidget);
    expect(find.text('Geofence Attendance System'), findsOneWidget);
    expect(find.text('Mark Attendance'), findsOneWidget);
    expect(find.text('Face Registration'), findsOneWidget);
    expect(find.text('Location Inspector (Get & Copy Lat/Long)'), findsOneWidget);
  });
}
