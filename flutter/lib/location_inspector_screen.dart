import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';

class LocationInspectorScreen extends StatefulWidget {
  const LocationInspectorScreen({super.key});

  @override
  State<LocationInspectorScreen> createState() => _LocationInspectorScreenState();
}

class _LocationInspectorScreenState extends State<LocationInspectorScreen> {
  String _latitude = "---";
  String _longitude = "---";
  bool _isLoading = false;
  String _errorMessage = "";

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      // 1. DEVICE SECURITY CHECK: Check for rooted/jailbroken devices and mock location apps
      bool isSafe = await SafeDevice.isSafeDevice;
      bool isMockLocationApp = await SafeDevice.isMockLocation;

      if (!isSafe || isMockLocationApp) {
        setState(() {
          _errorMessage = "Security Alert: Unsafe device or fake location app detected.";
          _isLoading = false;
        });
        return;
      }

      // 2. Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = "Location services are disabled on your device.";
          _isLoading = false;
        });
        return;
      }

      // 3. Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = "Location permissions are denied.";
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = "Location permissions are permanently denied.";
          _isLoading = false;
        });
        return;
      }

      // 4. Get exact position (UPDATED SYNTAX HERE)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // 5. GEOLOCATOR CHECK: Reject Mocked/Spoofed Locations explicitly
      if (position.isMocked) {
        setState(() {
          _errorMessage = "Fake location detected. Please disable mock locations or GPS spoofing apps.";
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _latitude = position.latitude.toString();
        _longitude = position.longitude.toString();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "An error occurred: $e";
        _isLoading = false;
      });
    }
  }
  void _copyToClipboard() {
    if (_latitude == "---" || _longitude == "---") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fetch location first!")),
      );
      return;
    }

    final coordinatesText = "$_latitude, $_longitude";
    Clipboard.setData(ClipboardData(text: coordinatesText));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Copied to clipboard: $coordinatesText"),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Location Inspector")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.my_location, size: 80, color: Colors.blue),
            const SizedBox(height: 24),

            // Display Card for Lat & Long
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      "Latitude: $_latitude",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Divider(height: 20),
                    Text(
                      "Longitude: $_longitude",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 32),

            // Fetch Location Button
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
              icon: const Icon(Icons.location_searching),
              label: const Text("Get Current Lat & Long"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _getCurrentLocation,
            ),

            const SizedBox(height: 16),

            // Copy Button
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text("Copy to Clipboard"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: _copyToClipboard,
            ),
          ],
        ),
      ),
    );
  }
}