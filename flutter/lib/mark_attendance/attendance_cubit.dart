import 'dart:io';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geo_face/api_constants.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:safe_device/safe_device.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'attendance_state.dart';

class AttendanceCubit extends Cubit<AttendanceState> {
  AttendanceCubit() : super(AttendanceInitial());

  // Office coordinates and allowed radius
  final double officeLat = 26.8740435;
  final double officeLng = 75.8173193;
  final double allowedRadiusInMeters = 50.0;

  // Must match the backend secret
  final String appSecret = "SUPER_SECRET_KEY_123!@#";

  void setImage(File image) {
    emit(AttendanceImageCaptured(image));
  }

  Future<void> submitAttendance(File capturedImage) async {
    emit(AttendanceLoading());

    try {
      // 1. DEVICE SECURITY CHECK (Root/Jailbreak & Fake GPS Apps)
      bool isSafe = await SafeDevice.isSafeDevice;
      bool isMockLocationApp = await SafeDevice.isMockLocation;

      if (!isSafe || isMockLocationApp) {
        emit(AttendanceLocationError("Security Alert: Unsafe device or fake location app detected.", capturedImage));
        return;
      }

      // 2. LOCATION PERMISSIONS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        emit(AttendanceLocationError("Location services are disabled.", capturedImage));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          emit(AttendanceLocationError("Location permissions are denied.", capturedImage));
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        emit(AttendanceLocationError("Location permissions are permanently denied.", capturedImage));
        return;
      }

      // 3. EXACT GPS CHECK (Added a timeout so it doesn't hang indoors)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception("Could not get GPS fix. Please step outside.");
      });

      // Explicitly reject mocked coordinates
      if (position.isMocked) {
        emit(AttendanceLocationError("Fake location detected. Please disable GPS spoofing.", capturedImage));
        return;
      }

      // 4. VERIFY GEOFENCE RADIUS
      double distanceInMeters = Geolocator.distanceBetween(
        officeLat,
        officeLng,
        position.latitude,
        position.longitude,
      );

      if (distanceInMeters > allowedRadiusInMeters) {
        emit(AttendanceLocationError(
            "You are not in the permitted location. Distance: ${distanceInMeters.toStringAsFixed(0)}m",
            capturedImage));
        return;
      }

      // 5. CALL THE REAL BACKEND API FOR ATTENDANCE & FACE MATCHING
      await _callAttendanceApi(capturedImage, position);

    } catch (e) {
      // Show the error, then revert the state so they can press the button again
      emit(AttendanceError(e.toString().replaceAll("Exception: ", "")));
      emit(AttendanceImageCaptured(capturedImage));
    }
  }

  Future<void> _callAttendanceApi(File image, Position position) async {
    var uri = Uri.parse('http://10.1.10.45:8000/api/attendance');
    var request = http.MultipartRequest('POST', uri);

    String empId = 'emp1'; // Make sure this is updated dynamically in a real app
    String lat = position.latitude.toString();
    String lng = position.longitude.toString();

    // ANTI-REPLAY PAYLOAD
    String timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    String nonce = const Uuid().v4();

    // HMAC SIGNATURE GENERATION
    String payload = "$empId|$lat|$lng|$timestamp|$nonce";
    var key = utf8.encode(appSecret);
    var bytes = utf8.encode(payload);
    var hmacSha256 = Hmac(sha256, key);
    String signature = hmacSha256.convert(bytes).toString();

    request.fields['employee_id'] = empId;
    request.fields['latitude'] = lat;
    request.fields['longitude'] = lng;
    request.fields['timestamp'] = timestamp;
    request.fields['nonce'] = nonce;
    request.fields['signature'] = signature;

    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    // Send the request with a timeout so it doesn't freeze the app on slow networks
    var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      emit(AttendanceSuccess());
    } else {
      // Parse the JSON error from backend nicely so it looks good in the UI
      String errorMessage = "Server error ${response.statusCode}";
      try {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        if (responseData.containsKey('detail')) {
          errorMessage = responseData['detail'].toString();
        }
      } catch (_) {
        errorMessage = response.body;
      }

      throw Exception(errorMessage);
    }
  }
}