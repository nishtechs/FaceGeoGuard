import os
import re
import shutil
import time
import hmac
import hashlib
import asyncio
from datetime import datetime

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from insightface.app import FaceAnalysis
import uvicorn

app = FastAPI()

# --- DIRECTORIES ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, "attendance_images")      # flat: <employee_id>_<timestamp>.jpg
REGISTERED_DIR = os.path.join(BASE_DIR, "registered_faces")   # per employee: registered_faces/<employee_id>/<photo>.jpg + .npy
TEMP_DIR = os.path.join(BASE_DIR, "temp_processing")

for directory in [UPLOAD_DIR, REGISTERED_DIR, TEMP_DIR]:
    os.makedirs(directory, exist_ok=True)

app.mount("/attendance_images", StaticFiles(directory=UPLOAD_DIR), name="attendance_images")
app.mount("/registered_faces", StaticFiles(directory=REGISTERED_DIR), name="registered_faces")

# --- SECURITY CONSTANTS ---
APP_SECRET = "SUPER_SECRET_KEY_123!@#"  # Must match the Flutter appSecret exactly
MAX_TIME_DIFF_SECONDS = 30
used_nonces = set()  # In production use Redis with a 30s TTL

# --- ARCFACE (InsightFace) ---
face_engine = FaceAnalysis(name="buffalo_l", providers=["CPUExecutionProvider"])
face_engine.prepare(ctx_id=-1, det_thresh=0.4, det_size=(640, 640))

# Cosine similarity threshold (0.68 = 68%)
SIMILARITY_THRESHOLD = 0.68

# Max reference photos kept per employee. Oldest are deleted when exceeded.
MAX_REFERENCE_PHOTOS = 5

EMPLOYEE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
IMAGE_EXTS = (".jpg", ".jpeg", ".png")


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
def validate_employee_id(employee_id: str) -> str:
    if not EMPLOYEE_ID_RE.match(employee_id):
        raise HTTPException(status_code=400, detail="Invalid employee_id format.")
    return employee_id


def employee_dir(employee_id: str) -> str:
    # Case-insensitive directory matching for employee_id
    if os.path.isdir(REGISTERED_DIR):
        for name in os.listdir(REGISTERED_DIR):
            if name.lower() == employee_id.lower() and os.path.isdir(os.path.join(REGISTERED_DIR, name)):
                return os.path.join(REGISTERED_DIR, name)
    return os.path.join(REGISTERED_DIR, employee_id)


def safe_remove(path: str):
    try:
        if os.path.exists(path):
            os.remove(path)
    except OSError:
        pass


class ImageReadError(ValueError):
    pass


class NoFaceError(ValueError):
    pass


ROTATIONS = [
    (None, "0"),
    (cv2.ROTATE_90_CLOCKWISE, "90"),
    (cv2.ROTATE_90_COUNTERCLOCKWISE, "270"),
    (cv2.ROTATE_180, "180"),
]


def get_embedding(image_path: str) -> np.ndarray:
    """L2-normalised 512-d ArcFace embedding of the largest face (tries 4 orientations)."""
    img = cv2.imread(image_path)
    if img is None:
        raise ImageReadError(
            f"Could not decode image ({os.path.getsize(image_path)} bytes). Send a JPEG/PNG."
        )
    print(f"   image shape: {img.shape}")

    h, w = img.shape[:2]
    if max(h, w) > 1600:
        scale = 1600 / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)))

    for rot_code, label in ROTATIONS:
        rotated = img if rot_code is None else cv2.rotate(img, rot_code)
        faces = face_engine.get(rotated)
        if faces:
            print(f"   face found at rotation {label}°")
            face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
            return face.normed_embedding.astype(np.float32)

    raise NoFaceError("No face detected in any orientation.")


def migrate_legacy_files(employee_id: str):
    """Old layout: registered_faces/<id>.jpg|.png|.npy  ->  registered_faces/<id>/legacy.*"""
    moved = False
    if os.path.isdir(REGISTERED_DIR):
        for fname in os.listdir(REGISTERED_DIR):
            fpath = os.path.join(REGISTERED_DIR, fname)
            if os.path.isfile(fpath):
                stem, ext = os.path.splitext(fname)
                if stem.lower() == employee_id.lower() and ext.lower() in (".jpg", ".png", ".jpeg", ".npy"):
                    target_folder = employee_dir(employee_id)
                    os.makedirs(target_folder, exist_ok=True)
                    shutil.move(fpath, os.path.join(target_folder, f"legacy{ext}"))
                    moved = True
    if moved:
        print(f"📦 Migrated legacy files for {employee_id} into {employee_dir(employee_id)}")


def list_reference_photos(employee_id: str) -> list[str]:
    """Sorted filenames (not paths) of the employee's reference photos."""
    migrate_legacy_files(employee_id)
    folder = employee_dir(employee_id)
    if not os.path.isdir(folder):
        return []
    return sorted(f for f in os.listdir(folder) if f.lower().endswith(IMAGE_EXTS))


def load_registered_embeddings(employee_id: str) -> list[np.ndarray]:
    """Embeddings of every reference photo. Missing .npy files are built from the photo."""
    embeddings = []
    folder = employee_dir(employee_id)
    for photo in list_reference_photos(employee_id):
        stem = os.path.splitext(photo)[0]
        emb_path = os.path.join(folder, f"{stem}.npy")
        if os.path.exists(emb_path):
            embeddings.append(np.load(emb_path))
            continue
        try:
            emb = get_embedding(os.path.join(folder, photo))
            np.save(emb_path, emb)
            embeddings.append(emb)
        except ValueError as e:
            print(f"⚠️ Skipping unusable reference photo {employee_id}/{photo}: {e}")
    return embeddings


def prune_old_photos(employee_id: str):
    photos = list_reference_photos(employee_id)
    folder = employee_dir(employee_id)
    while len(photos) > MAX_REFERENCE_PHOTOS:
        oldest = photos.pop(0)
        safe_remove(os.path.join(folder, oldest))
        safe_remove(os.path.join(folder, os.path.splitext(oldest)[0] + ".npy"))


# ------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------
@app.post("/api/attendance")
async def mark_attendance(
    latitude: str = Form(...),
    longitude: str = Form(...),
    employee_id: str = Form(...),
    timestamp: str = Form(...),
    nonce: str = Form(...),
    signature: str = Form(...),
    client_similarity_score: str | None = Form(None),
    image: UploadFile = File(...)
):
    temp_file_path = None
    try:
        validate_employee_id(employee_id)

        # SECURITY LAYER 1: REPLAY ATTACK PREVENTION
        if nonce in used_nonces:
            raise HTTPException(status_code=401, detail="Security Alert: Replay attack detected (Duplicate Nonce).")

        try:
            client_time_s = int(timestamp) / 1000.0
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid timestamp format.")
        if abs(time.time() - client_time_s) > MAX_TIME_DIFF_SECONDS:
            raise HTTPException(status_code=401, detail="Security Alert: Request expired.")

        # SECURITY LAYER 2: HMAC PAYLOAD VERIFICATION
        payload = f"{employee_id}|{latitude}|{longitude}|{timestamp}|{nonce}"
        expected_signature = hmac.new(
            key=APP_SECRET.encode("utf-8"),
            msg=payload.encode("utf-8"),
            digestmod=hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(expected_signature, signature):
            raise HTTPException(status_code=401, detail="Security Alert: Data tampering detected (Invalid Signature).")

        used_nonces.add(nonce)

        temp_file_path = os.path.join(TEMP_DIR, f"temp_{employee_id}_{nonce}.jpg")
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)

        similarity_display = client_similarity_score if client_similarity_score else "N/A"

        # If client performed on-device face matching, validate score
        if client_similarity_score:
            try:
                score_val = float(client_similarity_score)
                if score_val < 70.0:
                    raise HTTPException(status_code=401, detail="Client face match score below required threshold.")
            except ValueError:
                pass
        else:
            # SECURITY LAYER 3: ARCFACE RECOGNITION (Fallback to server-side verification)
            registered_embs = await asyncio.to_thread(load_registered_embeddings, employee_id)
            if registered_embs:
                try:
                    live_emb = await asyncio.to_thread(get_embedding, temp_file_path)
                    similarity = max(float(np.dot(live_emb, ref)) for ref in registered_embs)
                    if similarity < SIMILARITY_THRESHOLD:
                        print(f"❌ Mismatch for {employee_id} (best sim={similarity:.3f})")
                        raise HTTPException(status_code=401, detail="Face mismatch! Server ArcFace verification failed.")
                    similarity_display = f"{max(0.0, similarity) * 100:.2f}%"
                except (ImageReadError, NoFaceError) as e:
                    print(f"Server face check skipped/error: {e}")

        # SUCCESS: LOG ATTENDANCE
        timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        final_file_path = os.path.join(UPLOAD_DIR, f"{employee_id}_{timestamp_str}.jpg")
        shutil.move(temp_file_path, final_file_path)
        temp_file_path = None

        print(f"✅ ATTENDANCE LOGGED! {employee_id} at {latitude}, {longitude} (Client Similarity: {similarity_display})")

        return {
            "status": "success",
            "message": "Attendance verified and submitted securely!",
            "data": {
                "employee_id": employee_id,
                "similarity_score": similarity_display,
            },
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")
    finally:
        if temp_file_path:
            safe_remove(temp_file_path)


@app.post("/api/register")
async def register_employee(
    employee_id: str = Form(...),
    image: UploadFile = File(...),
    replace: bool = Form(False),  # true = delete the employee's existing reference photos first
):
    """Creates registered_faces/<employee_id>/ and adds one reference photo to it.
    Call it several times (different angles/lighting) to add more photos."""
    temp_file_path = None
    try:
        validate_employee_id(employee_id)

        temp_file_path = os.path.join(TEMP_DIR, f"temp_reg_{employee_id}.jpg")
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)

        print(f"🔍 Validating face for registration: {employee_id}...")

        try:
            embedding = await asyncio.to_thread(get_embedding, temp_file_path)
        except ImageReadError as e:
            print(f"⚠️ Registration image unreadable: {e}")
            raise HTTPException(status_code=400, detail=f"Uploaded file is not a valid image. {e}")
        except NoFaceError:
            debug_path = os.path.join(TEMP_DIR, f"failed_reg_{employee_id}.jpg")
            shutil.copy(temp_file_path, debug_path)
            print(f"⚠️ No face found. Saved rejected upload to {debug_path}")
            raise HTTPException(status_code=400, detail="No face detected in the photo. Please take a clear, well-lit photo.")

        migrate_legacy_files(employee_id)
        folder = employee_dir(employee_id)
        os.makedirs(folder, exist_ok=True)

        if replace:
            for f in os.listdir(folder):
                safe_remove(os.path.join(folder, f))

        stem = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        photo_path = os.path.join(folder, f"{stem}.jpg")
        shutil.move(temp_file_path, photo_path)
        temp_file_path = None
        np.save(os.path.join(folder, f"{stem}.npy"), embedding)

        prune_old_photos(employee_id)
        total = len(list_reference_photos(employee_id))

        print(f"✅ REGISTERED: {employee_id} ({total} reference photo(s))")

        return {
            "status": "success",
            "message": f"Employee {employee_id} registered successfully!",
            "data": {
                "employee_id": employee_id,
                "saved_path": photo_path,
                "total_reference_photos": total,
            },
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Registration Error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")
    finally:
        if temp_file_path:
            safe_remove(temp_file_path)


@app.get("/api/employee/{employee_id}/photos")
async def employee_photos(employee_id: str, request: Request):
    """Reference photo URLs for an employee.
    Response: {"employee_id": ..., "photos": [url, ...]}"""
    validate_employee_id(employee_id)
    photos = await asyncio.to_thread(list_reference_photos, employee_id)
    if not photos:
        raise HTTPException(status_code=404, detail=f"Employee {employee_id} not found in registry.")
    base = str(request.base_url).rstrip("/")
    return {
        "employee_id": employee_id,
        "photos": [f"{base}/registered_faces/{employee_id}/{p}" for p in photos],
    }


@app.post("/api/verify-face")
async def verify_face(
    employee_id: str = Form(...),
    image: UploadFile = File(...)
):
    """Deep Learning ArcFace Face Verification endpoint.
    Extracts 512-d embeddings and compares against employee's registered reference photos.
    """
    temp_file_path = None
    try:
        validate_employee_id(employee_id)

        registered_embs = await asyncio.to_thread(load_registered_embeddings, employee_id)
        if not registered_embs:
            raise HTTPException(
                status_code=404,
                detail=f"No registered reference photos found for Employee '{employee_id}'. Please register face first."
            )

        temp_file_path = os.path.join(TEMP_DIR, f"temp_verify_{employee_id}_{time.time_ns()}.jpg")
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)

        try:
            live_emb = await asyncio.to_thread(get_embedding, temp_file_path)
        except ImageReadError as e:
            raise HTTPException(status_code=400, detail=f"Uploaded file is not a valid image. {e}")
        except NoFaceError:
            raise HTTPException(status_code=400, detail="No face detected in photo. Please ensure face is clearly visible.")

        # Compute max cosine similarity against all registered reference photo embeddings
        raw_similarity = max(float(np.dot(live_emb, ref)) for ref in registered_embs)
        similarity_pct = round(max(0.0, raw_similarity) * 100.0, 1)
        is_match = raw_similarity >= SIMILARITY_THRESHOLD

        print(f"🔍 ArcFace Verify for '{employee_id}': sim={raw_similarity:.3f} ({similarity_pct}%), match={is_match}")

        return {
            "status": "success",
            "is_match": is_match,
            "similarity_score": raw_similarity,
            "similarity_percentage": similarity_pct,
            "threshold_percentage": round(SIMILARITY_THRESHOLD * 100.0, 1),
            "message": "ArcFace Match Passed" if is_match else "ArcFace Match Failed (Face does not match registered photographs)",
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Face Verify Error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")
    finally:
        if temp_file_path:
            safe_remove(temp_file_path)


@app.get("/api/image-links")
async def list_image_links(request: Request, folder: str, employee_id: str | None = None):
    """Lists direct URLs of images. folder = 'attendance' or 'registered'."""
    if folder not in ("attendance", "registered"):
        raise HTTPException(status_code=400, detail="folder must be 'attendance' or 'registered'.")

    base = str(request.base_url).rstrip("/")
    images = []

    if folder == "attendance":
        for f in sorted(os.listdir(UPLOAD_DIR)):
            if f.lower().endswith(IMAGE_EXTS) and (not employee_id or f.startswith(employee_id)):
                images.append({"filename": f, "url": f"{base}/attendance_images/{f}"})
    else:
        if employee_id:
            validate_employee_id(employee_id)
            emp_ids = [employee_id]
        else:
            emp_ids = sorted(d for d in os.listdir(REGISTERED_DIR) if os.path.isdir(employee_dir(d)))
        for emp in emp_ids:
            for p in list_reference_photos(emp):
                images.append({
                    "filename": f"{emp}/{p}",
                    "url": f"{base}/registered_faces/{emp}/{p}",
                })

    return {"count": len(images), "images": images}


if __name__ == "__main__":
    print("Starting Secure FastAPI + ArcFace (InsightFace) Server...")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)