# Geo Face — Geofence & Active Face Liveness Attendance System

A secure, enterprise-grade mobile attendance and employee registration platform combining **Flutter** (Frontend with active liveness & geofence checks) and **FastAPI + ArcFace InsightFace** (Backend deep-learning face recognition with HMAC security).

---

## 🌟 Key Features

### 📱 Flutter Mobile Application
- **Active Liveness Detection**: Utilizes `smart_liveliness_detection` for interactive real-time liveness challenges (blinking, head turns, tilting) to prevent photo/video spoofing attacks.
- **Strict Geofencing**: Enforces distance limits (50-meter radius) relative to office location coordinates using `geolocator`.
- **Anti-Spoofing & Device Attestation**: Uses `safe_device` to detect rooted/jailbroken devices and block fake GPS/mock location applications.
- **HMAC-SHA256 Payload Signing**: Generates dynamic signatures using a shared app secret, unique UUID nonces, and UTC timestamps to prevent replay & data tampering attacks.
- **On-Device Face Comparison**: Fetches reference photos from the API (`/api/employee/{empId}/photos`) and performs client-side verification before submitting attendance.
- **State Management**: Built using `flutter_bloc` (`AttendanceCubit` and `RegistrationCubit`) for clean architecture and predictable state management.
- **Features Included**:
  - 📷 **Daily Attendance**: Multi-step verification (Liveness -> Geofence -> ArcFace match).
  - 👤 **Employee Face Registration**: Enrolls new employees with multiple reference photos.
  - 📍 **Location Inspector**: Interactive tool to get & copy current high-accuracy Lat/Long coordinates.

### 🐍 FastAPI + ArcFace Backend
- **InsightFace ArcFace Engine**: Powered by the `buffalo_l` model generating L2-normalized 512-dimensional face embeddings.
- **Multi-Photo Reference Matching**: Supports multiple reference photos per employee for robust matching under varying lighting and angles.
- **Automatic Embedding Caching**: Computes and caches `.npy` binary embeddings alongside registered images for sub-second verification latency.
- **Replay Attack Defense**: Single-use nonce verification and 30-second timestamp freshness window.
- **Automatic Photo Pruning & Migration**: Keeps up to `MAX_REFERENCE_PHOTOS` (default: 5) per employee, automatically migrating legacy flat structures to organized directories.

---

## 🏗️ Verification Workflow

```
┌─────────────────────────┐
│  1. Face Liveness Check │ ➔ Interactive challenge (Blink, Turn, Tilt)
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│  2. Geofence Check      │ ➔ GPS check, Mock location detection, 50m radius
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│  3. Face Recognition    │ ➔ Device-end matching + FastAPI ArcFace verification
└─────────────────────────┘
```

---

## 📁 Project Structure

```
├── lib/
│   ├── main.dart                       # App entry point & Home Dashboard
│   ├── api_constants.dart              # Centralized API URLs & IP configuration
│   ├── front_camera_screen.dart        # Camera screen wrapping smart_liveliness_detection
│   ├── location_inspector_screen.dart  # Lat/Long Inspector & clipboard tool
│   ├── face_registration/
│   │   ├── face_registration_screen.dart # Employee Enrollment UI
│   │   ├── registration_cubit.dart       # Registration logic & state management
│   │   └── registration_state.dart       # Registration states
│   └── mark_attendance/
│       ├── attendance_screen.dart        # Daily Attendance UI
│       ├── attendance_cubit.dart         # Attendance submission logic & geofence
│       └── attendance_state.dart         # Attendance states
├── pubspec.yaml                        # Flutter dependencies
│
└── backend/ (Python FastAPI Server)
    ├── main.py                         # FastAPI server with ArcFace & HMAC verification
    ├── attendance_images/              # Logged attendance photos (<employee_id>_<timestamp>.jpg)
    ├── registered_faces/               # Reference photos & .npy embeddings per employee
    └── temp_processing/                # Temporary processing buffer
```

---

## 🔌 API Endpoints Reference

Base URL: `http://<SERVER_IP>:8000/api`

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `POST` | `/api/register` | Enrolls a new employee face photo. Pre-computes 512-d ArcFace embedding. |
| `POST` | `/api/attendance` | Validates HMAC signature, timestamp, nonce, location, and ArcFace cosine similarity (threshold >= 0.68). |
| `GET` | `/api/employee/{employee_id}/photos` | Returns JSON list of direct reference photo URLs for client-side comparison. |
| `GET` | `/api/image-links` | Utility route listing uploaded attendance and registered face URLs. |

---

## 🚀 Setup & Installation

### 1. Backend Setup (FastAPI + ArcFace)

#### Prerequisites
- Python 3.10+
- OpenCV & C++ build tools (for `insightface` and `onnxruntime`)

#### Installation
```bash
# Clone or navigate to server folder
cd backend

# Create virtual environment
python -m venv venv
# On Windows:
venv\Scripts\activate
# On Linux/macOS:
source venv/bin/activate

# Install dependencies
pip install fastapi uvicorn insightface opencv-python numpy onnxruntime staticfiles
```

#### Running the Server
```bash
python main.py
# Server will start on http://0.0.0.0:8000
```

---

### 2. Flutter App Setup

#### Prerequisites
- Flutter SDK 3.x+ (Dart SDK `>=3.0.0 <4.0.0`)
- Android Studio / VS Code with Flutter extension
- Connected Android/iOS physical device (camera & GPS required)

#### Configuration
Update `lib/api_constants.dart` with your local machine's IP address:
```dart
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'http://10.1.10.45:8000/api'; // Replace with your IP
  static const String registerFace = '$baseUrl/register';
  static const String verifyAttendance = '$baseUrl/attendance';
  static const String login = '$baseUrl/login';
}
```

#### Run the Application
```bash
# Get dependencies
flutter pub get

# Run static analysis
flutter analyze

# Execute unit / widget tests
flutter test

# Run app on connected device
flutter run
```

---

## 🔒 Security Architecture

1. **Replay Attack Prevention**: Every request includes a single-use UUID (`nonce`) and UTC `timestamp`. The server rejects duplicate nonces and requests older than 30 seconds.
2. **Data Tampering Protection**: Payload string (`employee_id|latitude|longitude|timestamp|nonce`) is signed using HMAC SHA-256 with `APP_SECRET`.
3. **Mock GPS & Root Guard**: Rejects mocked location providers (`position.isMocked`) and unsafe device environments (`SafeDevice.isSafeDevice`).
4. **ArcFace Embedding Verification**: Computes 512-d L2-normalized vectors and evaluates Cosine Similarity against all enrolled photos for the employee (`similarity >= 0.68`).

---




