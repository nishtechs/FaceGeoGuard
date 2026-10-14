import 'dart:io';

class RegistrationState {
  final File? capturedImage;
  final bool isLoading;
  final String message;
  final bool isSuccess;

  RegistrationState({
    this.capturedImage,
    this.isLoading = false,
    this.message = "",
    this.isSuccess = false,
  });

  // copyWith allows us to update only specific fields while keeping the rest the same
  RegistrationState copyWith({
    File? capturedImage,
    bool? isLoading,
    String? message,
    bool? isSuccess,
  }) {
    return RegistrationState(
      capturedImage: capturedImage ?? this.capturedImage,
      isLoading: isLoading ?? this.isLoading,
      message: message ?? this.message,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}