# yolo_obj.py
import os
import cv2
import base64
import numpy as np
import requests
from pathlib import Path
from ultralytics import YOLO

#custom weights file
model = YOLO("C:/Users/User/Downloads/FitChooseIntegrate/FitChooseIntegrate/backend/weight.model/best.pt")

# โฟลเดอร์สำหรับเก็บไฟล์ที่ Crop
output_dir = Path("cropped_images")
try:
    os.makedirs(output_dir, exist_ok=True)
    print(f"Output directory created/verified: {output_dir.absolute()}")
except Exception as e:
    print(f"Error creating output directory: {e}")
    import traceback
    traceback.print_exc()

async def download_image(image_url: str):
    """ดาวน์โหลดรูปภาพจาก URL และแปลงเป็น OpenCV image"""
    try:
        import aiohttp
        import numpy as np
        
        async with aiohttp.ClientSession() as session:
            async with session.get(image_url) as response:  # แก้ไขจาก url เป็น image_url
                if response.status == 200:
                    image_data = await response.read()
                    nparr = np.frombuffer(image_data, np.uint8)
                    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                    return img
                else:
                    print(f"Error downloading image: HTTP status {response.status}")
                    return None
    except Exception as e:
        print(f"Error downloading image: {e}")
        import traceback
        traceback.print_exc()
        return None

async def process_yolo(task_id: str, image_path: str, server_url: str):
    """ ประมวลผลรูปภาพด้วย YOLO และบันทึก Crop Image พร้อมคืน URL """
    try:
        print(f"Starting process_yolo for task {task_id}")
        print(f"Image path: {image_path}")
        
       # ตรวจสอบว่า image_path เป็น URL หรือไม่
        if image_path.startswith('http'):
            # ดาวน์โหลดรูปภาพจาก URL
            img = await download_image(image_path)
        else:
            # โหลดรูปภาพจากไฟล์โดยตรง
            img = cv2.imread(image_path)
        
        # ตรวจสอบว่า img เป็น None หรือไม่
        if img is None:
            print(f"Error: Failed to load image from path: {image_path}")
            return task_id, []  # คืนค่า empty list เมื่อไม่สามารถโหลดรูปภาพได้
        
        # ตรวจสอบว่า img มีข้อมูลหรือไม่
        if img.size == 0:
            print(f"Error: Loaded image is empty")
            return task_id, []
            
        print(f"Image shape: {img.shape}")
        
        # ประมวลผลด้วย YOLO
        results = model(img, conf=0.25)  # เพิ่ม confidence threshold
        
        detected_objects = []
        print(f"YOLO detected {len(results)} results")

        for idx, result in enumerate(results):
            boxes = result.boxes
            if boxes is None or len(boxes) == 0:
                print(f"No boxes detected in result {idx}")
                continue
                
            print(f"Processing result {idx} with {len(boxes)} boxes")
            
            for i in range(len(boxes)):
                try:
                    box = boxes.xyxy[i]
                    cls = boxes.cls[i]
                    
                    x1, y1, x2, y2 = map(int, box)
                    class_name = model.names[int(cls)]
                    print(f"Detected {class_name} at coordinates ({x1}, {y1}, {x2}, {y2})")
                    
                    # ตรวจสอบว่าพิกัดถูกต้องหรือไม่
                    if x1 >= x2 or y1 >= y2 or x1 < 0 or y1 < 0 or x2 > img.shape[1] or y2 > img.shape[0]:
                        print(f"Invalid coordinates: ({x1}, {y1}, {x2}, {y2}), image shape: {img.shape}")
                        continue
                        
                    cropped_img = img[y1:y2, x1:x2]
                    if cropped_img.size == 0:
                        print(f"Empty cropped image for {class_name}")
                        continue

                    # กำหนดประเภทเสื้อผ้า (upper, lower, dress)
                    garment_type = "unknown"
                    if class_name in ["shirt", "t-shirt", "jacket", "sweater", "hoodie", "top", "Upper"]:
                        garment_type = "upper"
                    elif class_name in ["pants", "jeans", "shorts", "skirt", "Lower"]:
                        garment_type = "lower"
                    elif class_name in ["dress", "Dress"]:
                        garment_type = "dress"
                    else:
                        print(f"Unknown class: {class_name}, skipping")
                        continue

                    # ตั้งชื่อไฟล์สำหรับ Crop Image
                    filename = f"{task_id}_{garment_type}_{i}.jpg"
                    file_path = output_dir / filename
                    print(f"Saving cropped image to {file_path}")

                    # บันทึกไฟล์
                    cv2.imwrite(str(file_path), cropped_img)
                    print(f"Cropped image saved successfully")

                    # URL ของรูปที่ Crop แล้ว
                    cropped_url = f"{server_url}/cropped_images/{filename}"
                    print(f"Cropped URL: {cropped_url}")

                    # เพิ่มข้อมูลลง Database (หากต้องการ)
                    detected_objects.append({
                        "class": class_name,
                        "garment_type": garment_type,
                        "cropped_image_url": cropped_url
                    })
                except Exception as e:
                    print(f"Error processing detection {i}: {e}")
                    import traceback
                    traceback.print_exc()

        print(f"process_yolo completed for task {task_id}, detected {len(detected_objects)} objects")
        return task_id, detected_objects
    except Exception as e:
        print(f"Error in process_yolo: {e}")
        import traceback
        traceback.print_exc()
        return task_id, []  # คืนค่า empty list เมื่อเกิดข้อผิดพลาด
