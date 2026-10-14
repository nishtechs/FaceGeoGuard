import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../front_camera_screen.dart';
import 'registration_cubit.dart';
import 'registration_state.dart';

class FaceRegistrationScreen extends StatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final TextEditingController _idController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  // Camera navigation stays in UI, but we pass the result to the Cubit
  Future<void> _openCameraForLiveness(BuildContext context) async {
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
      // Send the image to the Cubit
      context.read<RegistrationCubit>().setImage(fileToSave);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Provide the Cubit to the widget tree
    return BlocProvider(
      create: (context) => RegistrationCubit(),
      child: Scaffold(
        appBar: AppBar(title: const Text("Face Registration Module")),
        // Use Builder to access the Cubit provided just above
        body: Builder(
            builder: (context) {
              return Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  // BlocBuilder listens to state changes and rebuilds the UI
                  child: BlocBuilder<RegistrationCubit, RegistrationState>(
                    builder: (context, state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            "New Employee Enrollment",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),

                          TextField(
                            controller: _idController,
                            decoration: const InputDecoration(
                              labelText: "Employee ID (e.g. EMP123)",
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Preview Box for Captured Face
                          Container(
                            height: 250,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: state.capturedImage != null
                                ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(state.capturedImage!, fit: BoxFit.cover),
                            )
                                : const Center(
                              child: Text("No face captured yet", style: TextStyle(color: Colors.grey)),
                            ),
                          ),
                          const SizedBox(height: 16),

                          ElevatedButton.icon(
                            onPressed: () => _openCameraForLiveness(context),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text("Capture Face with Liveness"),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
                          ),
                          const SizedBox(height: 20),

                          state.isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                            onPressed: () {
                              context.read<RegistrationCubit>().submitRegistration(_idController.text.trim());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(14),
                            ),
                            child: const Text("Register to Database", style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(height: 20),

                          if (state.message.isNotEmpty)
                            Text(
                              state.message,
                              style: TextStyle(
                                color: state.isSuccess ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              );
            }
        ),
      ),
    );
  }
}