import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geo_face/api_constants.dart';
import 'package:geo_face/face_registration/registration_state.dart';
import 'package:http/http.dart' as http;

class RegistrationCubit extends Cubit<RegistrationState> {
  RegistrationCubit() : super(RegistrationState());

  void setImage(File file) {
    emit(state.copyWith(capturedImage: file, message: "", isSuccess: false));
  }

  Future<void> submitRegistration(String empId) async {
    if (empId.isEmpty) {
      emit(state.copyWith(message: "Please enter an Employee ID."));
      return;
    }
    if (state.capturedImage == null) {
      emit(state.copyWith(message: "Please capture your face photo first."));
      return;
    }

    emit(state.copyWith(isLoading: true, message: ""));

    try {
      var uri = Uri.parse(ApiConstants.registerFace);
      var request = http.MultipartRequest('POST', uri);

      request.fields['employee_id'] = empId;
      request.files.add(await http.MultipartFile.fromPath('image', state.capturedImage!.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        emit(state.copyWith(
          isSuccess: true,
          message: "Employee $empId registered successfully!",
          isLoading: false,
        ));
      } else {
        emit(state.copyWith(
          isSuccess: false,
          message: "Registration failed: ${response.body}",
          isLoading: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isSuccess: false,
        message: "Network error: $e",
        isLoading: false,
      ));
    }
  }
}