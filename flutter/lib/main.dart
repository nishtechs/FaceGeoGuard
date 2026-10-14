import 'package:flutter/material.dart';
import 'face_registration/face_registration_screen.dart';
import 'mark_attendance/attendance_screen.dart';
import 'location_inspector_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geofence Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
      ),
      home: const HomeDashboard(),
    );
  }
}

// A simple dashboard screen to navigate between features
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Attendance Portal")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_pin, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              "Geofence Attendance System",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Go to Attendance Screen
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text("Mark Attendance"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AttendanceScreen()),
                );
              },
            ),

            const SizedBox(height: 16),

            // Go to Face Registration Screen
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text("Face Registration"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FaceRegistrationScreen()),
                );
              },
            ),

            const SizedBox(height: 16),

            // Go to Location Inspector Screen
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location),
              label: const Text("Location Inspector (Get & Copy Lat/Long)"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LocationInspectorScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}