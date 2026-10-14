import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../front_camera_screen.dart';
import 'attendance_cubit.dart';
import 'attendance_state.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AttendanceCubit(),
      child: Scaffold(
        appBar: AppBar(title: const Text("Daily Attendance")),
        body: BlocConsumer<AttendanceCubit, AttendanceState>(
          listener: (context, state) {
            if (state is AttendanceSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Attendance Submitted Successfully!")),
              );
              Navigator.pop(context); // Or navigate to Home screen
            } else if (state is AttendanceLocationError) {
              _showLocationErrorDialog(context, state.message);
            } else if (state is AttendanceError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: Colors.red),
              );
            }
          },
          builder: (context, state) {
            if (state is AttendanceLoading) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Verifying location and matching face securely..."),
                  ],
                ),
              );
            }

            File? capturedImage;
            if (state is AttendanceImageCaptured) capturedImage = state.image;
            if (state is AttendanceLocationError) capturedImage = state.image;

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (capturedImage != null) ...[
                      // Show captured image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          capturedImage,
                          height: 300,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ONE SINGLE Submit Button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text("Submit Attendance"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: () => context.read<AttendanceCubit>().submitAttendance(capturedImage!),
                      ),

                      const SizedBox(height: 12),

                      // Retake button
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retake Photo"),
                        onPressed: () => _openCameraAndSetImage(context),
                      ),
                    ] else ...[
                      // Initial State: Capture Button
                      const Icon(Icons.camera_alt, size: 80, color: Colors.grey),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera),
                        label: const Text("Capture Photo"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: () => _openCameraAndSetImage(context),
                      ),
                    ]
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showLocationErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red),
            SizedBox(width: 8),
            Text("Geofence Alert"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // Camera Helper Method
  Future<void> _openCameraAndSetImage(BuildContext context) async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FrontCameraScreen()),
    );

    if (result == null) return;

    File? fileToSave;

    if (result is File) {
      fileToSave = result;
    } else if (result is String) {
      fileToSave = File(result);
    } else {
      try {
        fileToSave = File(result.path);
      } catch (e) {
        debugPrint("Could not parse returned file type.");
      }
    }

    if (fileToSave != null && context.mounted) {
      context.read<AttendanceCubit>().setImage(fileToSave);
    }
  }
}