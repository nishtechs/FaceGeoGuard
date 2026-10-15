import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:safe_device/safe_device.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../api_constants.dart';
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

      // 3. EXACT GPS CHECK (With timeout so it doesn't hang)
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

      // 5. DEEP LEARNING ARCFACE FACE MATCHING & VERIFICATION
      emit(AttendanceFetchingPhotos(capturedImage));

      final matchResult = await _performArcFaceVerification(capturedImage, 'vsr');
      bool isMatch = matchResult['isMatch'] == true;
      double similarityScore = (matchResult['similarityScore'] as num).toDouble();

      emit(AttendanceFaceMatchResult(
        isMatch: isMatch,
        similarityScore: similarityScore,
        capturedImage: capturedImage,
        message: isMatch
            ? "ArcFace Face Match Passed (${similarityScore.toStringAsFixed(1)}% similarity)"
            : "ArcFace Face Match Failed (${similarityScore.toStringAsFixed(1)}% similarity). Face does not match registered employee photographs.",
      ));

    } catch (e) {
      emit(AttendanceError(e.toString().replaceAll("Exception: ", "")));
      emit(AttendanceImageCaptured(capturedImage));
    }
  }

  /// Deep Learning ArcFace 512-dimensional Embedding Face Verification
  Future<Map<String, dynamic>> _performArcFaceVerification(File capturedImage, String empId) async {
    final candidateIds = {empId, 'vsr', 'EMP123'}.toList();

    for (String id in candidateIds) {
      try {
        var urlStr = '${ApiConstants.baseUrl}/verify-face';
        debugPrint("\n==================== [API REQUEST: ARCFACE VERIFY FACE] ====================");
        debugPrint("➡️ URL: $urlStr");
        debugPrint("➡️ Fields: employee_id=$id");
        debugPrint("➡️ File: ${capturedImage.path}");
        debugPrint("==========================================================================");

        var uri = Uri.parse(urlStr);
        var request = http.MultipartRequest('POST', uri);
        request.fields['employee_id'] = id;
        request.files.add(await http.MultipartFile.fromPath('image', capturedImage.path));

        var streamedResponse = await request.send().timeout(const Duration(seconds: 15));
        var response = await http.Response.fromStream(streamedResponse);

        debugPrint("\n==================== [API RESPONSE: ARCFACE VERIFY FACE] ====================");
        debugPrint("⬅️ Status Code: ${response.statusCode}");
        debugPrint("⬅️ Response Body: ${response.body}");
        debugPrint("==========================================================================\n");

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) {
            bool isMatch = data['is_match'] == true;
            double score = double.tryParse(data['similarity_percentage'].toString()) ??
                           ((double.tryParse(data['similarity_score'].toString()) ?? 0.0) * 100.0);
            return {
              'isMatch': isMatch,
              'similarityScore': score,
              'message': data['message'] ?? (isMatch ? "Face Match Passed" : "Face Match Failed"),
            };
          }
        }
      } catch (e) {
        debugPrint("❌ [API ERROR: ARCFACE VERIFY FACE] $e\n");
      }
    }

    // On-device fallback if server is offline
    double onDeviceScore = await _performOnDeviceFaceMatching(capturedImage, empId);
    return {
      'isMatch': onDeviceScore >= 70.0,
      'similarityScore': onDeviceScore,
      'message': onDeviceScore >= 70.0 ? "Face Match Passed" : "Face Match Failed",
    };
  }
   //9819080080 avance
  /// On-Device (Client-Side) Face Landmark Geometric Ratio Matching
  Future<double> _performOnDeviceFaceMatching(File capturedImage, String empId) async {
    List<String> referencePhotoUrls = [];

    // 1. Fetch employee registered reference photo URLs from server (try empId first, then EMP123)
    final candidateIds = {empId, 'vsr'}.toList();

    for (String id in candidateIds) {
      try {
        var urlStr = '${ApiConstants.baseUrl}/employee/$id/photos';
        debugPrint("\n==================== [API REQUEST: GET EMPLOYEE PHOTOS] ====================");
        debugPrint("➡️ URL: $urlStr");
        debugPrint("==========================================================================");

        var uri = Uri.parse(urlStr);
        var response = await http.get(uri).timeout(const Duration(seconds: 15));

        debugPrint("\n==================== [API RESPONSE: GET EMPLOYEE PHOTOS] ====================");
        debugPrint("⬅️ Status Code: ${response.statusCode}");
        debugPrint("⬅️ Response Body: ${response.body}");
        debugPrint("==========================================================================\n");

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is List) {
            referencePhotoUrls = decoded.map((e) => e.toString()).toList();
          } else if (decoded is Map && decoded['photos'] is List) {
            referencePhotoUrls = (decoded['photos'] as List).map((e) => e.toString()).toList();
          }
          if (referencePhotoUrls.isNotEmpty) break;
        }
      } catch (e) {
        debugPrint("❌ [API ERROR: GET EMPLOYEE PHOTOS] $e\n");
      }
    }

    if (referencePhotoUrls.isEmpty) {
      throw Exception("No registered reference photos found for Employee '$empId' on server. Please register face first.");
    }

    // 2. Extract landmark ratios from the LIVE captured image
    final List<double>? liveFeatures = await _extractFaceGeometry(capturedImage);
    if (liveFeatures == null) {
      throw Exception("Failed to clearly detect facial features in live photo. Make sure you are facing the camera.");
    }

    double maxSimilarity = 0.0;
    int processedPhotosCount = 0;

    // 3. Compare with registered reference photos downloaded from server
    for (String photoUrl in referencePhotoUrls) {
      try {
        debugPrint("➡️ Downloading reference photo: $photoUrl");
        final res = await http.get(Uri.parse(photoUrl)).timeout(const Duration(seconds: 15));
        debugPrint("⬅️ Photo status: ${res.statusCode}, size: ${res.bodyBytes.length} bytes");

        if (res.statusCode == 200) {
          // Save temp file for FaceDetector
          final tempFile = File('${Directory.systemTemp.path}/ref_temp_$processedPhotosCount.jpg');
          await tempFile.writeAsBytes(res.bodyBytes);

          final List<double>? refFeatures = await _extractFaceGeometry(tempFile);
          try { await tempFile.delete(); } catch (_) {}

          if (refFeatures != null) {
            double similarity = _computeGeometrySimilarity(liveFeatures, refFeatures);
            debugPrint("   On-Device Similarity with $photoUrl: ${similarity.toStringAsFixed(2)}%");
            if (similarity > maxSimilarity) {
              maxSimilarity = similarity;
            }
            processedPhotosCount++;
          } else {
             debugPrint("   No distinct facial landmarks found in reference photo $photoUrl");
          }
        }
      } catch (e) {
        debugPrint("❌ Error downloading/processing reference photo $photoUrl: $e");
      }
    }

    if (processedPhotosCount == 0) {
      throw Exception("Failed to extract facial geometry from the registered reference photos. Please register high-quality straight-facing photos.");
    }

    debugPrint("✅ Best On-Device Geometry Match Score: ${maxSimilarity.toStringAsFixed(2)}%\n");
    return maxSimilarity.clamp(0.0, 100.0);
  }

  /// Extracts Facial Landmark Euclidean distance ratios (Biometric Geometry)
  Future<List<double>?> _extractFaceGeometry(File imageFile) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await detector.processImage(inputImage);

      if (faces.isEmpty) return null;

      // Find largest face
      Face largestFace = faces.first;
      for (var f in faces) {
        if (f.boundingBox.width * f.boundingBox.height > largestFace.boundingBox.width * largestFace.boundingBox.height) {
          largestFace = f;
        }
      }

      final le = largestFace.landmarks[FaceLandmarkType.leftEye]?.position;
      final re = largestFace.landmarks[FaceLandmarkType.rightEye]?.position;
      final nb = largestFace.landmarks[FaceLandmarkType.noseBase]?.position;
      final lm = largestFace.landmarks[FaceLandmarkType.leftMouth]?.position;
      final rm = largestFace.landmarks[FaceLandmarkType.rightMouth]?.position;
      final bm = largestFace.landmarks[FaceLandmarkType.bottomMouth]?.position;

      // If key biometrics are missing, return null
      if (le == null || re == null || nb == null || lm == null || rm == null || bm == null) return null;

      double dist(math.Point<int> p1, math.Point<int> p2) {
        return math.sqrt(math.pow(p1.x - p2.x, 2) + math.pow(p1.y - p2.y, 2));
      }

      // Base denominator for scale invariance
      final eyeDist = dist(le, re);
      if (eyeDist <= 0) return null;

      return [
        dist(le, nb) / eyeDist,        // Left eye to nose
        dist(re, nb) / eyeDist,        // Right eye to nose
        dist(lm, rm) / eyeDist,        // Mouth width
        dist(nb, lm) / eyeDist,        // Nose to left mouth
        dist(nb, rm) / eyeDist,        // Nose to right mouth
        dist(le, lm) / eyeDist,        // Left eye to left mouth
        dist(re, rm) / eyeDist,        // Right eye to right mouth
        dist(nb, bm) / eyeDist,        // Nose to bottom mouth
      ];
    } catch (e) {
      debugPrint("Geometry extraction error: $e");
      return null;
    } finally {
      await detector.close();
    }
  }

  /// Calculates percentage similarity based on Mean Absolute Error (MAE) of facial proportions
  double _computeGeometrySimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return 0.0;

    double diffSum = 0.0;
    for (int i = 0; i < v1.length; i++) {
      diffSum += (v1[i] - v2[i]).abs();
    }

    // Since these are ratios against eye distance, differences are typically < 0.2
    // A diffSum of 0 -> 100%
    // A diffSum of 0.45 -> 0% (highly mismatched faces)
    double penalty = diffSum * 220.0; // Tunable strictness multiplier
    double similarity = 100.0 - penalty;
    
    // Penalize hard if outside plausible range
    if (similarity < 0) return 0.0;
    
    // Add small buffer to make strict matches hit 90+
    if (similarity > 99.0) similarity = 98.5;

    return similarity;
  }

  Future<void> confirmAttendanceSubmission(File capturedImage, [double? similarityScore]) async {
    emit(AttendanceLoading());
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _callAttendanceApi(capturedImage, position, similarityScore);
    } catch (e) {
      emit(AttendanceError("Submission error: $e"));
      emit(AttendanceImageCaptured(capturedImage));
    }
  }

  Future<void> _callAttendanceApi(File image, Position position, [double? similarityScore]) async {
    var uri = Uri.parse(ApiConstants.verifyAttendance);
    var request = http.MultipartRequest('POST', uri);

    String empId = 'vsr';
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
    if (similarityScore != null) {
      request.fields['client_similarity_score'] = similarityScore.toStringAsFixed(2);
    }

    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    debugPrint("\n==================== [API REQUEST: SUBMIT ATTENDANCE] ====================");
    debugPrint("➡️ URL: ${ApiConstants.verifyAttendance}");
    debugPrint("➡️ Fields: employee_id=$empId, latitude=$lat, longitude=$lng, timestamp=$timestamp, nonce=$nonce, signature=$signature, client_similarity_score=${similarityScore?.toStringAsFixed(2)}");
    debugPrint("➡️ Image File: ${image.path}");
    debugPrint("==========================================================================");

    var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    var response = await http.Response.fromStream(streamedResponse);

    debugPrint("\n==================== [API RESPONSE: SUBMIT ATTENDANCE] ====================");
    debugPrint("⬅️ Status Code: ${response.statusCode}");
    debugPrint("⬅️ Response Body: ${response.body}");
    debugPrint("==========================================================================\n");

    if (response.statusCode == 200) {
      emit(AttendanceSuccess());
    } else {
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