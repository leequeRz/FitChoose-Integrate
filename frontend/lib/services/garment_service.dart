import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:fitchoose/services/api_service.dart';

class GarmentService {
  final ApiService _apiService = ApiService();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // อัปโหลดรูปภาพเสื้อผ้าไปยัง Firebase Storage
  Future<String?> uploadGarmentImage(File imageFile, String garmentType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final userId = user.uid;

      // สร้างชื่อไฟล์ที่ไม่ซ้ำกัน
      final fileName =
          'garment_${userId}_${garmentType}_${DateTime.now().millisecondsSinceEpoch}${path.extension(imageFile.path)}';

      // กำหนด path ใน Firebase Storage
      final storageRef = _storage.ref().child('garment_images/$fileName');

      // อัปโหลดไฟล์
      final uploadTask = storageRef.putFile(imageFile);

      // รอจนกว่าการอัปโหลดจะเสร็จสิ้น
      final snapshot = await uploadTask;

      // รับ URL ของรูปภาพ
      final downloadUrl = await snapshot.ref.getDownloadURL();

      print('Garment image uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('Error uploading garment image: $e');
      return null;
    }
  }

  // เพิ่มเสื้อผ้าใหม่ลงใน MongoDB
  Future<bool> addGarment({
    required String garmentType,
    required String garmentImage,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userId = user.uid;
      final baseUrl = _apiService.baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/garments/create'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'user_id': userId,
          'garment_type': garmentType,
          'garment_image': garmentImage,
          'created_at': DateTime.now().toIso8601String(),
        }),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error adding garment: $e');
      return false;
    }
  }

  // ดึงข้อมูลเสื้อผ้าตามประเภท
  Future<List<Map<String, dynamic>>> getGarmentsByType(
      String garmentType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final userId = user.uid;
      final baseUrl = _apiService.baseUrl;

      final response = await http.get(
        Uri.parse('$baseUrl/garments/user/$userId/type/$garmentType'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('Error getting garments: $e');
      return [];
    }
  }

  // ลบเสื้อผ้า
  Future<bool> deleteGarment(String garmentId, String imageUrl) async {
    try {
      final baseUrl = _apiService.baseUrl;

      // ลบข้อมูลจาก MongoDB
      final response = await http.delete(
        Uri.parse('$baseUrl/garments/$garmentId'),
      );

      if (response.statusCode == 200) {
        // ลบรูปภาพจาก Firebase Storage
        if (imageUrl.isNotEmpty) {
          try {
            final ref = _storage.refFromURL(imageUrl);
            await ref.delete();
          } catch (e) {
            print('Error deleting garment image: $e');
          }
        }
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('Error deleting garment: $e');
      return false;
    }
  }

  // นับจำนวนเสื้อผ้าในแต่ละประเภท
  Future<int> countGarmentsByType(String garmentType) async {
    final garments = await getGarmentsByType(garmentType);
    return garments.length;
  }

  // ดึงข้อมูลเสื้อผ้าทั้งหมดสำหรับ Virtual Try-On
  Future<Map<String, List<Map<String, dynamic>>>>
      getAllGarmentsForVirtualTryOn() async {
    try {
      final Map<String, List<Map<String, dynamic>>> result = {
        'upper': [],
        'lower': [],
        'dress': [],
      };

      // ดึงข้อมูลเสื้อผ้าแต่ละประเภท
      result['upper'] = await getGarmentsByType('upper');
      result['lower'] = await getGarmentsByType('lower');
      result['dress'] = await getGarmentsByType('dress');

      return result;
    } catch (e) {
      print('Error getting all garments for virtual try-on: $e');
      return {
        'upper': [],
        'lower': [],
        'dress': [],
      };
    }
  }

  // ดึงข้อมูลเสื้อผ้าล่าสุดในแต่ละประเภทสำหรับ Virtual Try-On
  Future<Map<String, Map<String, dynamic>?>>
      getLatestGarmentsForVirtualTryOn() async {
    try {
      final Map<String, Map<String, dynamic>?> result = {
        'upper': null,
        'lower': null,
        'dress': null,
      };

      // ดึงข้อมูลเสื้อผ้าแต่ละประเภท
      final upperGarments = await getGarmentsByType('upper');
      final lowerGarments = await getGarmentsByType('lower');
      final dressGarments = await getGarmentsByType('dress');

      // เลือกเสื้อผ้าล่าสุดในแต่ละประเภท (ถ้ามี)
      if (upperGarments.isNotEmpty) {
        result['upper'] = upperGarments.first;
      }

      if (lowerGarments.isNotEmpty) {
        result['lower'] = lowerGarments.first;
      }

      if (dressGarments.isNotEmpty) {
        result['dress'] = dressGarments.first;
      }

      return result;
    } catch (e) {
      print('Error getting latest garments for virtual try-on: $e');
      return {
        'upper': null,
        'lower': null,
        'dress': null,
      };
    }
  }

  // ปรับปรุงฟังก์ชันบันทึกข้อมูล matching
  Future<Map<String, dynamic>> saveMatching(
      Map<String, dynamic> matchingData) async {
    try {
      print('Saving matching data: $matchingData');
      return await _apiService.createMatching(matchingData);
    } catch (e) {
      print('Error in saveMatching: $e');
      rethrow;
    }
  }

  // ปรับปรุงฟังก์ชันสำหรับดึงข้อมูลเสื้อผ้าตาม ID
  Future<Map<String, dynamic>?> getGarmentById(String garmentId) async {
    try {
      print('Getting garment with ID: $garmentId');
      final response = await http.get(
        Uri.parse('${_apiService.baseUrl}/garments/$garmentId'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print(
            'Failed to get garment: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error getting garment by ID: $e');
      return null;
    }
  }

  // เพิ่มฟังก์ชันสำหรับดึงประวัติ matching
  Future<List<Map<String, dynamic>>> getMatchingHistory(String userId) async {
    try {
      return await _apiService.getUserMatchings(userId);
    } catch (e) {
      print('Error getting matching history: $e');
      return [];
    }
  }

  // เพิ่มฟังก์ชันสำหรับอัปเดต favorite status
  Future<bool> updateFavoriteStatus(String matchingId, bool isFavorite) async {
    try {
      await _apiService.updateMatchingFavorite(matchingId, isFavorite);
      return true;
    } catch (e) {
      print('Error updating favorite status: $e');
      return false;
    }
  }

  // เพิ่มฟังก์ชันสำหรับอัปเดต matching detail
  Future<bool> updateMatchingDetail(
      String matchingId, String matchingDetail) async {
    try {
      await _apiService.updateMatchingDetail(matchingId, matchingDetail);
      return true;
    } catch (e) {
      print('Error updating matching detail: $e');
      return false;
    }
  }

  // เพิ่มฟังก์ชันสำหรับดึงข้อมูล matching ตาม ID
  Future<Map<String, dynamic>> getMatchingById(String matchingId) async {
    try {
      return await _apiService.getMatchingById(matchingId);
    } catch (e) {
      print('Error in getMatchingById: $e');
      rethrow;
    }
  }

  // เพิ่มฟังก์ชันสำหรับเพิ่ม favorite
  Future<bool> addToFavorites(String matchingId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        return false;
      }

      await _apiService.addFavorite(matchingId, userId);
      return true;
    } catch (e) {
      print('Error adding to favorites: $e');
      return false;
    }
  }

  // เพิ่มฟังก์ชันสำหรับลบ favorite
  Future<bool> removeFromFavorites(String matchingId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        return false;
      }

      await _apiService.removeFavorite(matchingId, userId);
      return true;
    } catch (e) {
      print('Error removing from favorites: $e');
      return false;
    }
  }

  // เพิ่มฟังก์ชันสำหรับดึงรายการ favorites
  Future<List<Map<String, dynamic>>> getFavorites() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        return [];
      }

      return await _apiService.getUserFavorites(userId);
    } catch (e) {
      print('Error getting favorites: $e');
      return [];
    }
  }

  // เพิ่มฟังก์ชันลบ matching
  Future<bool> deleteMatching(String matchingId) async {
    try {
      final baseUrl = _apiService.baseUrl;
      final response = await http.delete(
        Uri.parse('$baseUrl/matchings/$matchingId'),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Failed to delete matching: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error deleting matching: $e');
      return false;
    }
  }

  // อัปโหลดรูปภาพชั่วคราวไปยัง Firebase Storage
  Future<String?> uploadTempImage(File imageFile) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'temp_${userId}_$timestamp.jpg';
      final ref = FirebaseStorage.instance.ref().child('temp_images/$fileName');

      // อัปโหลดรูปภาพ
      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask.whenComplete(() => null);

      // รับ URL ของรูปภาพพร้อม token
      final downloadUrl = await snapshot.ref.getDownloadURL();
      print('Uploaded image URL: $downloadUrl'); // เพิ่ม log เพื่อตรวจสอบ URL
      return downloadUrl;
    } catch (e) {
      print('Error uploading temp image: $e');
      return null;
    }
  }

  // ตรวจจับเสื้อผ้าด้วย YOLO API
  Future<Map<String, dynamic>> detectGarment(File imageFile,
      {String? imageUrl}) async {
    final baseUrl = _apiService.baseUrl;
    try {
      // ถ้าไม่มี imageUrl ให้อัปโหลดรูปภาพก่อน
      String? url = imageUrl;
      if (url == null) {
        url = await uploadTempImage(imageFile);
        if (url == null) {
          return {'message': 'failed', 'error': 'Failed to upload image'};
        }
      }

      // ส่งรูปภาพโดยตรงแทนการส่ง URL
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/yolo'));
      request.files
          .add(await http.MultipartFile.fromPath('file', imageFile.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        return {
          'message': 'failed',
          'error': 'API Error: ${response.statusCode}'
        };
      }
    } catch (e) {
      print('Error detecting garment: $e');
      return {'message': 'failed', 'error': e.toString()};
    }
  }

  // เพิ่มเมธอดสำหรับบันทึกเสื้อผ้าที่ตรวจจับได้จาก YOLO
  Future<List<String>> saveDetectedGarments(List<dynamic> detections) async {
    print('Saving detected garments: $detections');
    final savedTypes = <String>[];

    for (final detection in detections) {
      print('Processing detection: $detection');
      final className = detection['class'] as String;
      final imageUrl = detection['cropped_image_url'] as String;
      print('Class name: $className, Image URL: $imageUrl');

      // กำหนดประเภทเสื้อผ้าตามชื่อคลาส
      String garmentType = 'unknown';

      // รองรับทั้งชื่อคลาสแบบเดิมและชื่อคลาสจาก YOLO โมเดลใหม่
      if (['shirt', 't-shirt', 'jacket', 'sweater', 'hoodie', 'top', 'Upper']
          .contains(className)) {
        garmentType = 'upper';
      } else if (['pants', 'jeans', 'shorts', 'skirt', 'Lower']
          .contains(className)) {
        garmentType = 'lower';
      } else if (['dress', 'Dress'].contains(className)) {
        garmentType = 'dress';
      }

      print('Mapped to garment type: $garmentType');

      if (garmentType != 'unknown') {
        print('Attempting to add garment of type: $garmentType');
        final success = await addGarment(
          garmentType: garmentType,
          garmentImage: imageUrl,
        );

        print('Add garment result: $success');
        if (success) {
          // แปลงประเภทเสื้อผ้าเป็นภาษาไทยสำหรับการแสดงผล
          String displayType = '';
          if (garmentType == 'upper') {
            displayType = 'เสื้อ';
          } else if (garmentType == 'lower') {
            displayType = 'กางเกง/กระโปรง';
          } else if (garmentType == 'dress') {
            displayType = 'ชุดเดรส';
          } else {
            displayType = garmentType;
          }

          savedTypes.add(displayType);
        }
      } else {
        print('Unknown garment class: $className, skipping');
      }
    }

    print('Saved types: $savedTypes');
    return savedTypes;
  }
}
