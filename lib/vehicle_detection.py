# File: vehicle_detection.py
import cv2
import torch
import requests

# Load YOLOv5 model
model = torch.hub.load('ultralytics/yolov5', 'yolov5s', pretrained=True)
cap = cv2.VideoCapture(0)

# Node.js server API endpoint (replace with your actual Render URL)
API_URL = "https://traffic-server-f1fs.onrender.com/update_traffic"

# Your API key (same as in your Node.js .env file)
API_KEY = "Qs9jL2nAd73d8X9vMnWQ8JzpF9b4Kz7ER2DMD0MDndJw"  # <-- replace this with your actual API key

CAMERA_ID = "Camera_1"
LAT, LON = 10.816955, 78.693905
last_count = -1

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Run YOLOv5 inference
    results = model(frame)
    df = results.pandas().xyxy[0]

    # Count vehicles (classes: 2=car, 3=motorbike, 5=bus, 7=truck)
    count = df[df['class'].isin([2, 3, 5, 7])].shape[0]

    # Display detection and count overlay
    frame = results.render()[0]
    frame = cv2.UMat(frame).get()
    cv2.putText(frame, f"Vehicles: {count}", (20, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 2)
    cv2.imshow("Vehicle Detection", frame)

    # Send update only if count changed
    if count != last_count:
        payload = {
            "location": CAMERA_ID,
            "vehicleCount": count,
            "latitude": LAT,
            "longitude": LON,
        }
        headers = {
            "x-api-key": API_KEY
        }
        try:
            r = requests.post(API_URL, json=payload, headers=headers)
            print(f"📡 Sent → {count} | Response: {r.status_code} {r.text}")
        except Exception as e:
            print("❌ Error sending data:", e)
        last_count = count

    # Break loop on 'q' key
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# Cleanup
cap.release()
cv2.destroyAllWindows()
