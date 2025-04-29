# FitChooseIntegrate

## การติดตั้ง

### ดาวน์โหลดไฟล์โมเดล

ก่อนรันแอปพลิเคชัน คุณจำเป็นต้องดาวน์โหลดไฟล์โมเดล YOLO:

1. ดาวน์โหลดไฟล์ `best.pt` จาก [Google Drive](https://drive.google.com/file/d/YOUR_FILE_ID/view?usp=sharing)
2. สร้างโฟลเดอร์ `backend/weight.model/` ในโปรเจค
3. วางไฟล์ `best.pt` ในโฟลเดอร์ `backend/weight.model/`

### Backend

1. ติดตั้ง dependencies:
   ```bash
   cd backend
   pip install -r requirements.txt