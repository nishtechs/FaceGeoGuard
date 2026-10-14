import 'dart:io';
import 'package:flutter/foundation.dart';

@immutable
abstract class AttendanceState {}

class AttendanceInitial extends AttendanceState {}

class AttendanceImageCaptured extends AttendanceState {
  final File image;

  AttendanceImageCaptured(this.image);
}

class AttendanceLoading extends AttendanceState {}

class AttendanceSuccess extends AttendanceState {}

class AttendanceError extends AttendanceState {
  final String message;

  AttendanceError(this.message);
}

class AttendanceLocationError extends AttendanceState {
  final String message;
  final File image; // Keep the image so we don't lose it on a location error
  AttendanceLocationError(this.message, this.image);
}

class AttendanceFetchingPhotos extends AttendanceState {
  final File image;
  AttendanceFetchingPhotos(this.image);
}

class AttendanceFaceMatchResult extends AttendanceState {
  final bool isMatch;
  final double similarityScore;
  final File capturedImage;
  final String message;

  AttendanceFaceMatchResult({
    required this.isMatch,
    required this.similarityScore,
    required this.capturedImage,
    required this.message,
  });
}
