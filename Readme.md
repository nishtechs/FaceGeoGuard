# GeoFaceAuth

Face recognition attendance system with liveness verification and geofencing for secure, location-based identity authentication and attendance tracking.

## 🎯 Overview

GeoFaceAuth is a comprehensive biometric attendance solution that combines facial recognition, liveness detection, and geofencing to create a secure, fraud-resistant attendance tracking system. It prevents spoofing attacks and ensures attendance is only recorded when users are physically present at designated locations.

## ✨ Features

- **Facial Registration & Enrollment** — Users register their facial features for future authentication
- **Real-Time Face Matching** — Live camera-based facial recognition and matching
- **Liveness Detection** — Anti-spoofing verification to ensure a real person is authenticating (not a photo/video)
- **Geofencing** — GPS-based location verification to enforce location constraints
- **Location-Based Attendance** — Attendance only recorded when user is within authorized geofence boundaries
- **Attendance Logging** — Complete attendance history with timestamps and location data
- **User Management** — Dashboard for user registration, profile management, and role assignment
- **Fraud Prevention** — Multi-layer security combining biometrics + location verification
- **Real-Time Dashboard** — View attendance status and analytics

## 🔒 Security Features

- Liveness verification prevents photo/video spoofing attacks
- Geofencing ensures location authenticity
- Encrypted credential storage
- Secure API authentication
- Role-based access control (RBAC)

## 🚀 Tech Stack

- **Backend:** Python, Flask/Django
- **Face Recognition:** OpenCV, face_recognition library, TensorFlow
- **Liveness Detection:** [Specify your library - e.g., MediaPipe, custom CNN]
- **Geofencing:** GPS/Location APIs
- **Database:** PostgreSQL/MongoDB
- **Frontend:** React/Vue.js (if applicable)
- **Deployment:** Docker, AWS/GCP

## 📋 Requirements

- Python 3.8+
- OpenCV
- face_recognition
- numpy
- requests
- flask
- [Add other dependencies]

## 🔧 Installation

### 1. Clone the Repository
```bash
git clone https://github.com/nishtechs/GeoFaceAuth.git
cd GeoFaceAuth
