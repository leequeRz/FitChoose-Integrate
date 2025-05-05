from fastapi import FastAPI, APIRouter, HTTPException, Body, Request, Response, File, UploadFile, Form
from configuration import user_collection, garment_collection, matching_collection,favorite_collection, virtualtryon_collection
from database.schemas import all_users, user_data
from database.models import UserModel, UserUpdateModel, Garment, MatchingModel, FavoriteModel, VirtualTryOnModel
from bson.objectid import ObjectId
from datetime import datetime
from fastapi.middleware.cors import CORSMiddleware
#models
from typing import Union
from contextlib import asynccontextmanager
from pydantic import BaseModel
import asyncio
import uvicorn
from typing import Dict, List, Any
import random
import time
from ultralytics import YOLO
from yolo_obj import process_yolo
import os
from fastapi.staticfiles import StaticFiles
from uuid import uuid4
#virtual try-on
from fastapi.responses import FileResponse, JSONResponse
import shutil
import requests
import uuid
import traceback
from bson import ObjectId
import json
 
app = FastAPI()
app.task_queue = asyncio.Queue()

task_id = str
results: Dict[task_id, Any] = {}

# เปลี่ยนจาก localhost:8000 เป็น IP ที่สามารถเข้าถึงได้จากอุปกรณ์มือถือ
# ถ้าทดสอบบน emulator ให้ใช้ 10.0.2.2:8000
SERVER_URL = "http://10.0.2.2:8000"  # สำหรับ Android Emulator
# หรือใช้ IP ของเครื่องที่รัน server เช่น
# SERVER_URL = "http://192.168.1.xxx:8000"  # แทนที่ xxx ด้วย IP จริงของเครื่อง

# ให้ FastAPI เปิด folder cropped_images ให้เข้าถึงได้ทาง URL
app.mount("/cropped_images", StaticFiles(directory="cropped_images"), name="cropped_images")
app.mount("/virtual_tryon_results", StaticFiles(directory="virtual_tryon_results"), name="virtual_tryon_results")

# Virtual Try-On
# External Try-On API Endpoint
EXTERNAL_API_URL = "https://creating-joseph-tribune-assumption.trycloudflare.com/tryon"
# Folder to store result
RESULT_DIR = "C:/Users/User/Downloads/FitChooseIntegrate/FitChooseIntegrate/backend/virtual_tryon_results"
os.makedirs(RESULT_DIR, exist_ok=True)

router = APIRouter()

# class Item(BaseModel):
#     name: str
#     price: float
#     is_offer: Union[bool, None] = None

class A(BaseModel): # สร้าง BaseModel ของ YOLO
    image_url: str

class B(BaseModel): # สร้าง BaseModel ของ Virtual Try
    task_id: str
    text: str
    
class response(BaseModel):
    message: str

async def yolo(a: A):
    await asyncio.sleep(5)
    return task_id, a.text

async def virtual_try(b: B):
    await asyncio.sleep(2)
    return b.task_id, b.text
    
async def task_worker():
    global results
    while True:
        try:
            task = await app.task_queue.get()
            try:
                print(f"Processing task...")
                task_result = await task()
                
                # ตรวจสอบว่า task_result เป็น tuple ที่มี 2 ค่าหรือไม่
                if isinstance(task_result, tuple) and len(task_result) == 2:
                    task_id, result = task_result
                    print(f"Task completed: {task_id}, result type: {type(result)}")
                    
                    # ตรวจสอบว่า result เป็น None หรือไม่
                    if result is None:
                        print(f"Warning: Task {task_id} returned None result")
                        results[task_id] = []
                    else:
                        results[task_id] = result
                        
                    print(f"Result stored in results dict with key: {task_id}")
                else:
                    print(f"Error: Invalid task result format: {task_result}")
            except Exception as e:
                print(f"Error processing task: {e}")
                import traceback
                traceback.print_exc()
                
                # ถ้าเกิดข้อผิดพลาด ให้เก็บข้อความข้อผิดพลาดไว้ใน results
                # แต่ต้องมี task_id ก่อน
                if 'task_id' in locals():
                    results[task_id] = {"error": str(e)}
            finally:
                app.task_queue.task_done()
        except Exception as e:
            print(f"Critical error in task_worker: {e}")
            import traceback
            traceback.print_exc()
            await asyncio.sleep(1)  # หยุดสักครู่ก่อนทำงานต่อ

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(task_worker())

# Object Detection API Endpoint
# เขียน endpoint รับข้อมูลจาก client(รูป)
# เขียน BaseModel รับข้อมูลจาก client
@app.post("/yolo")
async def yolorequest(a: A):
    task_id = str(uuid4())
    
    # ใส่ task ลงใน queue โดยส่ง image_url แทนไฟล์
    await app.task_queue.put(lambda: process_yolo(task_id, a.image_url, SERVER_URL))
    start = time.time()
    
    # เพิ่ม logging เพื่อดูการทำงาน (แก้ไขให้ใช้ image_url แทน temp_file_path)
    print(f"Task {task_id} added to queue with image URL: {a.image_url}")
    
    try:
        while True:
            # เพิ่ม logging ทุก 5 วินาที
            if int(time.time() - start) % 5 == 0:
                print(f"Waiting for task {task_id}, elapsed time: {time.time() - start:.2f}s")
                print(f"Current results keys: {list(results.keys())}")
                
            if time.time() - start > 30:  # เพิ่ม timeout เป็น 30 วินาที
                return {"message": "timeout", "task_id": task_id}
                
            if task_id in results:
                result = results.pop(task_id)
                print(f"Task {task_id} completed with result: {result}")
                return {"message": "success", "detections": result}
                
            # เพิ่ม sleep เพื่อลดการใช้ CPU
            await asyncio.sleep(0.2)
    finally:
        pass

# Virtual Try-On API Endpoint
@app.post("/tryon")
async def tryon(
    human_img: UploadFile = File(...),
    garm_img: UploadFile = File(...),
    category: str = Form(...)
):
    try:
        # แปลงค่า category ให้ตรงกับที่ API ต้องการ
        category_mapping = {
            "Upper-Body": "upper_body",
            "Lower-Body": "lower_body",
            "Dress": "dresses"
        }
        
        # ใช้ค่าที่แปลงแล้ว หรือใช้ค่าเดิมถ้าไม่มีในการแปลง
        mapped_category = category_mapping.get(category, category)
        # Save uploaded files temporarily
        temp_human_path = os.path.join(RESULT_DIR, "temp_human.jpg")
        temp_garm_path = os.path.join(RESULT_DIR, "temp_garment.jpg")

        with open(temp_human_path, "wb") as f:
            shutil.copyfileobj(human_img.file, f)

        with open(temp_garm_path, "wb") as f:
            shutil.copyfileobj(garm_img.file, f)

        # Reopen for POSTing to external API
        with open(temp_human_path, "rb") as human_file, open(temp_garm_path, "rb") as garment_file:
            files = {
                "human_img": ("human.jpg", human_file, "image/jpeg"),
                "garm_img": ("garment.jpg", garment_file, "image/jpeg")
            }
            # ใช้ค่า category ที่แปลงแล้ว
            data = {"category": mapped_category}

            response = requests.post(EXTERNAL_API_URL, files=files, data=data)

        if response.status_code == 200:
            # Save output with timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            result_path = os.path.join(RESULT_DIR, f"result_tryon_{timestamp}.png")

            with open(result_path, "wb") as out_file:
                out_file.write(response.content)

            return FileResponse(result_path, media_type="image/png", filename=os.path.basename(result_path))
        else:
            return JSONResponse(status_code=response.status_code, content={"error": response.text})

    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})

# เพิ่ม endpoint สำหรับบันทึกผลลัพธ์ Virtual Try-On
@app.post("/virtualtryon/save")
async def save_virtual_tryon_result(data: dict):
    try:
        # แปลง ObjectId เป็น string ก่อนส่งกลับ
        result = virtualtryon_collection.insert_one(data)
        return {"id": str(result.inserted_id), "message": "Virtual try-on result saved successfully"}
    except Exception as e:
        print(f"Error saving virtual try-on result: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่มฟังก์ชันนี้เพื่อแปลง ObjectId เป็น string
class JSONEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, ObjectId):
            return str(o)
        return super().default(o)

@app.get("/virtualtryon/user/{user_id}")
async def get_virtual_tryon_history(user_id: str):
    try:
        # ใช้ virtualtryon_collection แทน virtual_tryon_collection
        results = list(virtualtryon_collection.find({"user_id": user_id}))
        
        # แปลง ObjectId เป็น string ก่อนส่งกลับ
        for result in results:
            result["_id"] = str(result["_id"])
            # แปลง ObjectId อื่นๆ ถ้ามี
            if "garment_id" in result and isinstance(result["garment_id"], ObjectId):
                result["garment_id"] = str(result["garment_id"])
        
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม endpoint สำหรับลบประวัติ Virtual Try-On
@app.delete("/virtualtryon/{virtualtryon_id}")
async def delete_virtualtryon(virtualtryon_id: str):
    try:
        # แปลง string ID เป็น ObjectId
        object_id = ObjectId(virtualtryon_id)
        
        # ค้นหาข้อมูลก่อนลบเพื่อเก็บ URL รูปภาพ
        virtualtryon_data = virtualtryon_collection.find_one({"_id": object_id})
        
        if not virtualtryon_data:
            raise HTTPException(status_code=404, detail="Virtual try-on record not found")
        
        # ลบข้อมูลจาก MongoDB
        result = virtualtryon_collection.delete_one({"_id": object_id})
        
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Virtual try-on record not found")
        
        # ลบรูปภาพจาก Firebase Storage (ถ้ามี URL)
        if "result_image" in virtualtryon_data and virtualtryon_data["result_image"]:
            # ส่งคำขอลบรูปภาพไปยัง Firebase (ต้องมีการจัดการเพิ่มเติม)
            # ในที่นี้เราจะไม่ลบรูปภาพจาก Firebase เนื่องจากต้องใช้ Firebase Admin SDK
            pass
        
        return {"message": "Virtual try-on record deleted successfully"}
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid ID format")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Mobile Application Endpoints all below
@router.get("/")
async def home():
    return {"message": "Welcome to FastAPI"}

# User Endpoints
@router.get("/users")
async def get_all_users():
    """ดึงข้อมูลผู้ใช้ทั้งหมด"""
    data = user_collection.find({"is_deleted": False})
    return all_users(data)

@router.get("/users/{user_id}")
async def get_user(user_id: str):
    """ดึงข้อมูลผู้ใช้ตาม ID"""
    try:
        # ตรวจสอบว่า user_id เป็น ObjectId หรือ Firebase UID
        if len(user_id) == 24 and all(c in '0123456789abcdefABCDEF' for c in user_id):
            # ถ้าเป็น ObjectId
            user = user_collection.find_one({"_id": ObjectId(user_id), "is_deleted": False})
        else:
            # ถ้าเป็น Firebase UID
            user = user_collection.find_one({"user_id": user_id, "is_deleted": False})
        
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # แปลง ObjectId เป็น string เพื่อให้ส่งกลับเป็น JSON ได้กับ
        user["_id"] = str(user["_id"])
        return user
    except Exception as e:
        print(f"Error getting user: {e}")
        raise HTTPException(status_code=500, detail=f"An error occurred: {e}")

@router.post("/users/create")
async def create_user(new_user: UserModel):
    """สร้างผู้ใช้ใหม่"""
    try:
        user_dict = dict(new_user)
        if "_id" in user_dict:
            del user_dict["_id"]
        # user_dict["created_at"] = int(datetime.timestamp(datetime.now()))
        # user_dict["updated_at"] = user_dict["created_at"]
        # user_dict["is_deleted"] = False
        
        resp = user_collection.insert_one(user_dict)
        return {"status_code": 200, "id": str(resp.inserted_id), "message": "User created successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"An error occurred: {e}")

@router.delete("/users/{user_id}")
async def delete_user(user_id: str):
    """ลบผู้ใช้ (soft delete)"""
    try:
        id = ObjectId(user_id)
        existing_user = user_collection.find_one({"_id": id, "is_deleted": False})
        if not existing_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_collection.update_one({"_id": id}, {"$set": {"is_deleted": True}})
        return {"status_code": 200, "message": "User deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"An error occurred: {e}")

@router.get("/users/check/{firebase_uid}")
async def check_user_exists(firebase_uid: str):
    """ตรวจสอบว่ามีผู้ใช้ที่มี Firebase UID นี้อยู่แล้วหรือไม่"""
    try:
        print(f"Checking if user exists with firebase_uid: {firebase_uid}")
        user = user_collection.find_one({"user_id": firebase_uid, "is_deleted": False})
        
        if user:
            print(f"User found: {user}")
            # แปลง ObjectId เป็น string เพื่อให้ส่งกลับเป็น JSON ได้กับ
            user["_id"] = str(user["_id"])
            return {"exists": True, "user_data": user}
        
        print(f"No user found with firebase_uid: {firebase_uid}")
        return {"exists": False}
    except Exception as e:
        print(f"Error checking user exists: {e}")
        raise HTTPException(status_code=500, detail=f"An error occurred: {e}")

@router.put("/users/update-by-firebase-uid/{firebase_uid}")
async def update_user_by_firebase_uid(firebase_uid: str, updated_user: UserUpdateModel):
    """อัปเดตข้อมูลผู้ใช้โุง Firebase UID"""
    try:
        existing_user = user_collection.find_one({"user_id": firebase_uid, "is_deleted": False})
        if not existing_user:
            raise HTTPException(status_code=404, detail="User not found")
        
        # กรองเฉพาะฟิลด์ที่มีค่า
        update_data = {k: v for k, v in dict(updated_user).items() if v is not None}
        # update_data["updated_at"] = datetime.timestamp(datetime.now())

        # ลบฟิลด์ที่ไม่ควรบันทึกลงในฐานข้อมูล
        if 'model_config' in update_data:
            del update_data['model_config']
        
        user_collection.update_one({"user_id": firebase_uid}, {"$set": update_data})
        return {"status_code": 200, "message": "User updated successfully"}
    except Exception as e:
        print(f"Error updating user: {e}")
        raise HTTPException(status_code=500, detail=f"An error occurred: {e}")

# Garment endpoints
@router.post("/garments/create")
async def create_garment(garment_data: dict = Body(...)):
    try:
        print(f"Received garment data: {garment_data}")
        
        # ตรวจสอบข้อมูลที่จำเป็น
        if not all(key in garment_data for key in ["user_id", "garment_type", "garment_image"]):
            missing_keys = [key for key in ["user_id", "garment_type", "garment_image"] if key not in garment_data]
            print(f"Missing required fields: {missing_keys}")
            raise HTTPException(status_code=400, detail=f"Missing required fields: {missing_keys}")
        
        # ตรวจสอบประเภทเสื้อผ้า
        if garment_data["garment_type"] not in ["upper", "lower", "dress"]:
            print(f"Invalid garment type: {garment_data['garment_type']}")
            raise HTTPException(status_code=400, detail="Invalid garment type")
        
        # เพิ่มเวลาที่สร้าง
        if "created_at" not in garment_data:
            garment_data["created_at"] = datetime.now().isoformat()
        
        # บันทึกลงใน MongoDB
        result = garment_collection.insert_one(garment_data)
        print(f"Garment created with ID: {result.inserted_id}")
        
        # ส่งคืน ID ของเสื้อผ้าที่สร้าง
        return {"garment_id": str(result.inserted_id), "message": "Garment created successfully"}
    except Exception as e:
        print(f"Error creating garment: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการดึงข้อมูลเสื้อผ้าตาม ID
@router.get("/garments/{garment_id}")
async def get_garment_by_id(garment_id: str):
    try:
        garment = garment_collection.find_one({"_id": ObjectId(garment_id)})
        if not garment:
            raise HTTPException(status_code=404, detail="Garment not found")
        
        # แปลง ObjectId เป็น string
        garment["_id"] = str(garment["_id"])
        return garment
    except Exception as e:
        print(f"Error getting garment: {e}")
        raise HTTPException(status_code=500, detail=str(e))


#get_garments_by_type
@router.get("/garments/user/{user_id}/type/{garment_type}")
async def get_garments_by_type(user_id: str, garment_type: str):
    try:
        # ตรวจสอบประเภทเสื้อผ้า
        if garment_type not in ["upper", "lower", "dress"]:
            raise HTTPException(status_code=400, detail="Invalid garment type")
        
        # ค้นหาเสื้อผ้าตามประเภทและ user_id
        garments = garment_collection.find({"user_id": user_id, "garment_type": garment_type})
        
        # แปลงเป็น list และเพิ่ม _id
        result = []
        for garment in garments:
            garment["_id"] = str(garment["_id"])
            result.append(garment)
        
        return result
    except Exception as e:
        print(f"Error getting garments: {e}")
        raise HTTPException(status_code=500, detail=str(e))

#delete_garment
@router.delete("/garments/{garment_id}")
async def delete_garment(garment_id: str):
    try:
        # ลบเสื้อผ้าตาม ID
        result = garment_collection.delete_one({"_id": ObjectId(garment_id)})
        
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Garment not found")
        
        return {"message": "Garment deleted successfully"}
    except Exception as e:
        print(f"Error deleting garment: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการบันทึก matching
@router.post("/matchings/create")
async def create_matching(matching_data: MatchingModel):
    try:
        # รับข้อมูลจาก request - เข้าถึงโดยตรง
        user_id = matching_data.user_id
        garment_top = matching_data.garment_top
        garment_bottom = matching_data.garment_bottom
        matching_result = matching_data.matching_result
        matching_detail = matching_data.matching_detail
        matching_date = matching_data.matching_date
        is_favorite = matching_data.is_favorite if hasattr(matching_data, 'is_favorite') else False
        
        # ตรวจสอบว่ามีการเลือกเสื้อผ้าอย่างน้อย 1 ชิ้น
        if not garment_top and not garment_bottom:
            raise HTTPException(status_code=400, detail="At least one garment is required")
            
        # สร้าง matching ใหม่
        new_matching = {
            "user_id": user_id,
            "garment_top": garment_top,
            "garment_bottom": garment_bottom,
            "matching_result": matching_result,
            "matching_detail": matching_detail,
            "matching_date": matching_date or datetime.now().isoformat(),
            "is_favorite": is_favorite
        }
        
        # บันทึกลงใน MongoDB
        result = matching_collection.insert_one(new_matching)
        matching_id = str(result.inserted_id)
        
        # ส่งข้อมูลกลับไปยัง client
        return {
            "status": "success",
            "matching_id": matching_id,
            "message": "Matching created successfully"
        }
        
    except Exception as e:
        print(f"Error creating matching: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการดึงข้อมูล matching ตาม ID
@router.get("/matchings/{matching_id}")
async def get_matching(matching_id: str):
    try:
        matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
        if not matching:
            raise HTTPException(status_code=404, detail="Matching not found")
        
        # แปลง ObjectId เป็น string
        matching["_id"] = str(matching["_id"])
        return matching
    except Exception as e:
        print(f"Error getting matching: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการดึงข้อมูล matching ทั้งหมดของผู้ใช้
@router.get("/matchings/user/{user_id}")
async def get_user_matchings(user_id: str):
    try:
        matchings = matching_collection.find({"user_id": user_id}).sort("matching_date", -1)
        
        # แปลงเป็น list และแปลง ObjectId เป็น string
        result = []
        for matching in matchings:
            matching["_id"] = str(matching["_id"])
            result.append(matching)
        
        return result
    except Exception as e:
        print(f"Error getting user matchings: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการอัปเดตสถานะ favorite
@router.put("/matchings/{matching_id}/favorite")
async def update_favorite(matching_id: str, data: FavoriteModel):
    try:
        is_favorite = data.is_favorite  # เปลี่ยนจาก .get() เป็นการเข้าถึงโดยตรง
        
        # ตรวจสอบว่ามี matching นี้หรือไม่
        matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
        if not matching:
            raise HTTPException(status_code=404, detail="Matching not found")
        
        # อัปเดตสถานะ favorite
        matching_collection.update_one(
            {"_id": ObjectId(matching_id)}, 
            {"$set": {"is_favorite": is_favorite}}
        )
        
        # ดึงข้อมูลที่อัปเดตแล้ว
        updated_matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
        updated_matching["_id"] = str(updated_matching["_id"])
        
        return updated_matching
    except Exception as e:
        print(f"Error updating favorite status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการอัปเดต matching detail
@router.put("/matchings/{matching_id}/detail")
async def update_matching_detail(matching_id: str, data: dict):
    try:
        matching_detail = data.get("matching_detail")
        if not matching_detail:
            raise HTTPException(status_code=400, detail="Matching detail is required")
        
        # ตรวจสอบว่ามี matching นี้หรือไม่
        matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
        if not matching:
            raise HTTPException(status_code=404, detail="Matching not found")
        
        # อัปเดต matching detail
        matching_collection.update_one(
            {"_id": ObjectId(matching_id)}, 
            {"$set": {"matching_detail": matching_detail}}
        )
        
        # ดึงข้อมูลที่อัปเดตแล้ว
        updated_matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
        updated_matching["_id"] = str(updated_matching["_id"])
        
        return updated_matching
    except Exception as e:
        print(f"Error updating matching detail: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม route สำหรับการลบ matching
@router.delete("/matchings/{matching_id}")
async def delete_matching(matching_id: str):
    try:
        # ตรวจสอบว่ามี matching นี้หรือไม่
        matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
        if not matching:
            raise HTTPException(status_code=404, detail="Matching not found")
        
        # ลบ matching
        matching_collection.delete_one({"_id": ObjectId(matching_id)})
        
        return {"message": "Matching deleted successfully"}
    except Exception as e:
        print(f"Error deleting matching: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม endpoint สำหรับเพิ่ม favorite
@router.post("/favorites/add")
async def add_favorite(favorite: FavoriteModel):
    try:
        # ตรวจสอบว่ามี favorite นี้อยู่แล้วหรือไม่
        existing_favorite = favorite_collection.find_one({
            "matching_id": favorite.matching_id,
            "user_id": favorite.user_id
        })
        
        if existing_favorite:
            return {"message": "This matching is already in favorites"}
        
        # เพิ่ม favorite ใหม่
        favorite_data = {
            "matching_id": favorite.matching_id,
            "user_id": favorite.user_id,
            "created_at": datetime.now().isoformat()
        }
        
        result = favorite_collection.insert_one(favorite_data)
        
        # อัปเดตสถานะ is_favorite ใน matching_collection
        matching_collection.update_one(
            {"_id": ObjectId(favorite.matching_id)},
            {"$set": {"is_favorite": True}}
        )
        
        return {
            "message": "Added to favorites successfully",
            "favorite_id": str(result.inserted_id)
        }
    except Exception as e:
        print(f"Error adding favorite: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม endpoint สำหรับลบ favorite
@router.delete("/favorites/remove")
async def remove_favorite(matching_id: str, user_id: str):
    try:
        # ลบ favorite
        result = favorite_collection.delete_one({
            "matching_id": matching_id,
            "user_id": user_id
        })
        
        if result.deleted_count == 0:
            return {"message": "Favorite not found"}
        
        # อัปเดตสถานะ is_favorite ใน matching_collection
        matching_collection.update_one(
            {"_id": ObjectId(matching_id)},
            {"$set": {"is_favorite": False}}
        )
        
        return {"message": "Removed from favorites successfully"}
    except Exception as e:
        print(f"Error removing favorite: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม endpoint สำหรับดึงรายการ favorites ของผู้ใช้
@router.get("/favorites/user/{user_id}")
async def get_user_favorites(user_id: str):
    try:
        # ดึงรายการ favorite ของผู้ใช้
        favorites = list(favorite_collection.find({"user_id": user_id}))
        
        # แปลง ObjectId เป็น string
        for favorite in favorites:
            favorite["_id"] = str(favorite["_id"])
        
        # ดึงข้อมูล matching ที่เป็น favorite
        favorite_matchings = []
        for favorite in favorites:
            matching_id = favorite["matching_id"]
            matching = matching_collection.find_one({"_id": ObjectId(matching_id)})
            
            if matching:
                matching["_id"] = str(matching["_id"])
                favorite_matchings.append(matching)
        
        return favorite_matchings
    except Exception as e:
        print(f"Error getting user favorites: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# เพิ่ม CORS middleware ให้ถูกต้อง
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # ในการผลิตจริง ควรระบุ origins ที่อนุญาตเท่านั้น
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
