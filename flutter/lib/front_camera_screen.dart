import 'dart:ffi';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_liveliness_detection/smart_liveliness_detection.dart';

class FrontCameraScreen extends StatefulWidget {
  const FrontCameraScreen({super.key});

  @override
  State<FrontCameraScreen> createState() => _FrontCameraScreenState();
}

class _FrontCameraScreenState extends State<FrontCameraScreen> {
  List<CameraDescription>? _frontCameras;
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _initLiveness();
  }

  Future<void> _initLiveness() async {
    // 1. Ensure camera permission using permission_handler
    final hasPermission = await _ensureCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Camera permission is required for liveness check.";
        });
      }
      return;
    }

    // 2. Fetch available cameras and filter for front camera
    try {
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).toList();

      if (front.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No front camera found on this device.";
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _frontCameras = front;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to initialize camera: $e";
        });
      }
    }
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (!mounted) return false;
    if (status.isPermanentlyDenied) {
      final open = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Camera permission needed'),
          content: const Text(
            'Enable camera access in Settings to verify your identity.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (open == true) await openAppSettings();
    }
    return false;
  }

  Future<void> _handleFinalImageCaptured(String sessionId, dynamic capturedData, dynamic data) async {
    debugPrint("📸 Liveness completed & captured! Data type: ${capturedData?.runtimeType}, data: ${data?.runtimeType}");

    try {
      File? capturedFile;

      if (capturedData is XFile) {
        capturedFile = File(capturedData.path);
      } else if (capturedData is File) {
        capturedFile = capturedData;
      } else if (capturedData is String) {
        capturedFile = File(capturedData);
      } else if (data is XFile) {
        capturedFile = File(data.path);
      } else if (data is File) {
        capturedFile = data;
      } else if (data is String) {
        capturedFile = File(data);
      } else if (capturedData is Uint8List) {
        final tempDir = Directory.systemTemp;
        capturedFile = File('${tempDir.path}/liveness_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await capturedFile.writeAsBytes(capturedData);
      }

      if (capturedFile != null && await capturedFile.exists()) {
        if (mounted) {
          Navigator.pop(context, capturedFile);
          return;
        }
      }

      _showToast("Verification successful!", Colors.green);
      if (mounted) {
        Navigator.pop(context, capturedFile);
      }
    } catch (e) {
      debugPrint("❌ Error in _handleFinalImageCaptured: $e");
      _showToast("Verification complete", Colors.green);
      if (mounted) {
        Navigator.pop(context, null);
      }
    }
  }

  void _showToast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text("Liveness Check"),
          backgroundColor: Colors.black,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_errorMessage.isNotEmpty || _frontCameras == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text("Liveness Check"),
          backgroundColor: Colors.black,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = "";
                    });
                    _initLiveness();
                  },
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            LivenessDetectionScreen(
              cameras: _frontCameras!,
              config: LivenessConfig(
                challengeTypes: [
                  ChallengeType.blink,
                  // ChallengeType.turnLeft,
                  // ChallengeType.turnRight,
                  // ChallengeType.tiltUp,
                ],
                numberOfRandomChallenges: 2,
                alwaysIncludeBlink: true,
                challengeInstructions: {
                  ChallengeType.blink: 'Blink 2–3 times quickly',
                  // ChallengeType.turnLeft: 'Slowly turn head left ←',
                  // ChallengeType.turnRight: 'Now turn head right →',
                  // ChallengeType.tiltUp: 'Look up slightly',
                },
                eyeBlinkThresholdOpen: 0.75,
                eyeBlinkThresholdClosed: 0.25,
                headTurnThreshold: 12.0,
                ovalHeightRatio: 0.65,
                ovalWidthRatio: 0.55,
                strokeWidth: 2.0,
                maxSessionDuration: const Duration(seconds: 90),
                messages: const LivenessMessages(
                  initialInstruction: 'Position your face inside the oval',
                  noFaceDetected: 'No face found — center yourself',
                  poorLighting: 'Too dark — move to better light',
                  moveCloser: 'Come closer',
                  moveFartherAway: 'Move back a bit',
                  perfectHoldStill: 'Great! Stay still',
                  verificationComplete: 'Verification successful!',
                  processingVerification: 'Finalizing...',
                  spoofingDetected: 'Suspicious — please try again',
                  errorInitializingCamera: 'Camera issue — check permissions',
                ),
              ),
              theme: LivenessTheme(
                primaryColor: Colors.blueAccent,
                successColor: Colors.green.shade600,
                errorColor: Colors.redAccent,
                warningColor: Colors.orangeAccent,
                ovalGuideColor: Colors.white.withValues(alpha: 0.95),
                backgroundColor: Colors.black87,
                instructionTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
                ),
                guidanceTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                progressIndicatorColor: Colors.blueAccent,
                progressIndicatorHeight: 8,
                useOvalPulseAnimation: true,
              ),

              onChallengeCompleted: (challenge) {
                debugPrint('Challenge completed: $challenge');
              },
              onManualImageCaptured: (sessionId, imageFile) {
                debugPrint("sessionId:$sessionId");
                debugPrint("image path:${imageFile.path}");
              },
              captureFinalImage: true,
              onLivenessCompleted: (sessionId, isSuccessful, extra) {
                if (isSuccessful) {
                  debugPrint("✅ Liveness passed! Extra data: $extra");

                  if (mounted) {
                    _showToast("Verification successful!", Colors.green);

                    File? finalCapturedFile;

                    // 1. extra is a Map. Let's dig inside it to find the image path!
                    // Check if extra is actually a map
                    if (extra is Map) {
                      // 1. Extract the nested map under the "antiSpoofingDetection" key
                      final antiSpoofingData = extra['antiSpoofingDetection'];

                      // 2. Verify the nested map exists before trying to read from it
                      if (antiSpoofingData is Map) {

                        // 3. Extract each specific value (using ?? false as a safe fallback)
                        bool isScreenGlare = antiSpoofingData['screenGlareDetected'] ?? false;
                        bool isLackOfContours = antiSpoofingData['lackOfFacialContoursDetected'] ?? false;
                        bool isMotionFailed = antiSpoofingData['motionCorrelationCheckFailed'] ?? false;
                        bool isScreenFlash = antiSpoofingData['screenFlashSpoofDetected'] ?? false;
                        bool isDepthSpoof = antiSpoofingData['depthSpoofDetected'] ?? false;

                        // You can now use these variables
                        debugPrint("Screen Glare Detected: $isScreenGlare");
                        debugPrint("Depth Spoof Detected: $isDepthSpoof");

                        // Example logic: Check if ANY spoofing was detected
                        bool isSuspicious = isScreenGlare || isLackOfContours || isMotionFailed || isScreenFlash || isDepthSpoof;

                        if (isSuspicious) {
                          debugPrint("Warning: Spoofing attempt detected!");
                        } else {
                          debugPrint("Liveness checks passed cleanly.");
                        }
                      }
                    }

                      // Navigator.pop(context, finalCapturedFile);
                      // Navigator.pop(context, null);

                  }
                } else {
                  if (mounted) {
                    _showToast("Liveness challenges failed. Please try again.", Colors.red);
                  }
                }
              },
              // showCaptureImageButton: true,
              // captureButtonText: 'Capture Final Photo',
              onFinalImageCaptured: (sessionId, imageFile, data) => _handleFinalImageCaptured(sessionId, imageFile, data),
            ),
          ],
        ),
      ),
    );
  }
}
