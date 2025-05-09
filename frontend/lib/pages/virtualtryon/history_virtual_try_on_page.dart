import 'package:flutter/material.dart';
import 'package:fitchoose/services/garment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:fitchoose/pages/virtualtryon/virtual_tryon_result_page.dart';

class HistoryVirtualTryOnPage extends StatefulWidget {
  const HistoryVirtualTryOnPage({Key? key}) : super(key: key);

  @override
  State<HistoryVirtualTryOnPage> createState() =>
      _HistoryVirtualTryOnPageState();
}

class _HistoryVirtualTryOnPageState extends State<HistoryVirtualTryOnPage> {
  final GarmentService _garmentService = GarmentService();
  List<Map<String, dynamic>> virtualTryOnHistory = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVirtualTryOnHistory();
  }

  // เพิ่มฟังก์ชันสำหรับดูผลลัพธ์ Virtual Try-On ในหน้าประวัติ
  // จากปัญหาที่คุณพบว่าเมื่อกดดูประวัติ Virtual Try-On ไม่ว่าจะกดที่ประวัติอันไหนก็จะแสดงผลลัพธ์เป็นรูปเดียวกันทั้งหมด ผมวเคราะห์สาเหตุและวิธีแก้ไขดังนี้
  //
  // ## สาเหตุของปัญหา
  //
  // จากโค้ดที่ได้เพิ่มไปก่อนหน้านี้ในไฟล์ `history_virtual_try_on_page.dart` มีความเป็นไปได้ว่าเกิดจากสาเหตุดังนี้:
  //
  // 1. **การตั้งชื่อไฟล์ชั่วคราวซ้ำกัน**: เมื่อดาวน์โหลดรูปภาพจาก URL มาเก็บเป็นไฟล์ชั่วคราว เราใช้ชื่อไฟล์เดียวกันทุกครั้ง (`temp_tryon_result.png`) ทำให้ไฟล์ถูกเขียนทับกัน
  //
  // 2. **การแคชรูปภาพ**: Flutter อาจจะแคชรูปภาพที่โหลดมาแล้ว ทำให้แสดงรูปเดิมแม้ว่า URL จะเปลี่ยนไป
  //
  // ## วิธีแก้ไข
  //
  // เราจะแก้ไขฟังก์ชัน `_viewVirtualTryOnResult` ในไฟล์ `history_virtual_try_on_page.dart` ดังนี้:
  Future<void> _viewVirtualTryOnResult(
      Map<String, dynamic> virtualTryOn) async {
    try {
      setState(() {
        isLoading = true;
      });

      final resultImageUrl = virtualTryOn['result_image'];
      final garmentId = virtualTryOn['garment_id'];
      final timestamp = DateTime.now()
          .millisecondsSinceEpoch; // เพิ่มตัวแปรเวลาเพื่อป้องกันการแคช

      if (resultImageUrl == null || resultImageUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่พบรูปภาพผลลัพธ์'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }

      // ดาวน์โหลดรูปภาพจาก URL
      final response = await http.get(Uri.parse(resultImageUrl +
          '?t=$timestamp')); // เพิ่มพารามิเตอร์เวลาเพื่อป้องกันการแคช
      if (response.statusCode != 200) {
        throw Exception('ไม่สามารถดาวน์โหลดรูปภาพได้');
      }

      // สร้างไฟล์ชั่วคราวสำหรับเก็บรูปภาพ โดยใช้ชื่อไฟล์ที่ไม่ซ้ำกัน
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
          '${tempDir.path}/temp_tryon_result_${virtualTryOn['id'] ?? timestamp}.png');
      await tempFile.writeAsBytes(response.bodyBytes);

      // ดึงข้อมูลเสื้อผ้า
      final garment = await _garmentService.getGarmentById(garmentId);
      if (garment == null) {
        throw Exception('ไม่พบข้อมูลเสื้อผ้า');
      }

      // กำหนดประเภทเสื้อผ้า
      String category = 'Unknown';
      if (garment['garment_type'] == 'upper') {
        category = 'Upper-Body';
      } else if (garment['garment_type'] == 'lower') {
        category = 'Lower-Body';
      } else if (garment['garment_type'] == 'dress') {
        category = 'Dress';
      }

      setState(() {
        isLoading = false;
      });

      // นำทางไปยังหน้าผลลัพธ์
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VirtualTryOnResultPage(
            resultImage: tempFile,
            selectedGarment: garment,
            category: category,
          ),
        ),
      );
    } catch (e) {
      print('Error viewing Virtual Try-On result: $e');
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ฟังก์ชันสำหรับลบประวัติ Virtual Try-On
  Future<void> _deleteVirtualTryOn(String virtualTryOnId) async {
    setState(() {
      isLoading = true;
    });

    try {
      // ค้นหารายการที่จะลบเพื่อเก็บ URL รูปภาพก่อนลบข้อมูล
      final itemToDelete = virtualTryOnHistory.firstWhere(
        (item) => item['_id'] == virtualTryOnId,
        orElse: () => {},
      );

      // เก็บ URL รูปภาพไว้ก่อนลบข้อมูล
      final resultImageUrl = itemToDelete['result_image'];
      print('Image URL to delete: $resultImageUrl');

      // ลบข้อมูลจาก MongoDB
      final success = await _garmentService.deleteVirtualTryOn(virtualTryOnId);

      if (success) {
        // ลบรายการออกจาก state
        setState(() {
          virtualTryOnHistory
              .removeWhere((item) => item['_id'] == virtualTryOnId);
          isLoading = false;
        });

        // ลบรูปภาพจาก Firebase Storage
        if (resultImageUrl != null && resultImageUrl.isNotEmpty) {
          try {
            // สร้าง reference จาก URL
            final ref = FirebaseStorage.instance.refFromURL(resultImageUrl);
            print('Deleting image from path: ${ref.fullPath}');

            // ลบไฟล์
            await ref.delete();
            print('Image deleted successfully from Firebase Storage');
          } catch (storageError) {
            print('Error deleting image from Firebase Storage: $storageError');
            // ไม่ต้องแสดง error เพราะข้อมูลใน MongoDB ถูกลบแล้ว
          }
        }

        // แสดงข้อความแจ้งเตือนว่าลบสำเร็จ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบประวัติการลองเสื้อผ้าเสร็จสิ้น'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          isLoading = false;
        });

        // แสดงข้อความแจ้งเตือนว่าลบไม่สำเร็จ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'ไม่สามารถลบประวัติการลองเสื้อผ้าได้ กรุณาลองใหม่อีกครั้ง'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error deleting Virtual Try-On: $e');
      setState(() {
        isLoading = false;
      });

      // แสดงข้อความแจ้งเตือนเมื่อเกิดข้อผิดพลาด
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // เพิ่มฟังก์ชันโหลดประวัติ virtual try-on
  Future<void> _loadVirtualTryOnHistory() async {
    setState(() {
      isLoading = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // เรียกใช้ service เพื่อดึงประวัติ virtual try-on
        final history = await _garmentService.getVirtualTryOnHistory();

        // พิมพ์ข้อมูลเพื่อตรวจสอบ
        print('Virtual Try-On History: $history');
        print('History length: ${history.length}');
        if (history.isNotEmpty) {
          print('First item: ${history[0]}');
        }

        setState(() {
          virtualTryOnHistory = history;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading Virtual Try-On history: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F0FF),
        elevation: 0,
        title: const Text(
          'Virtual Try-On History',
          style: TextStyle(
            color: Color(0xFF3B1E54),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3B1E54)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF9B7EBD)),
            )
          : virtualTryOnHistory.isEmpty
              ? const Center(
                  child: Text(
                    'No virtual try-on history found',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF3B1E54),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: virtualTryOnHistory.length,
                  itemBuilder: (context, index) {
                    final virtualTryOn = virtualTryOnHistory[index];
                    // เพิ่ม print เพื่อตรวจสอบข้อมูลที่ได้รับ
                    print('Rendering virtual try-on item: $virtualTryOn');

                    // ตรวจสอบว่ามี result_image หรือไม่
                    if (virtualTryOn['result_image'] == null ||
                        virtualTryOn['result_image'].isEmpty) {
                      print('Missing result_image for item: $virtualTryOn');
                      return const SizedBox
                          .shrink(); // ข้ามรายการที่ไม่มีรูปภาพ
                    }

                    // ดึงข้อมูลที่จำเป็นจาก virtualTryOn
                    final resultImage = virtualTryOn['result_image'];
                    final garmentId = virtualTryOn['garment_id'];
                    final tryOnId = virtualTryOn['_id'] ??
                        virtualTryOn['id']; // รองรับทั้งสองรูปแบบ

                    // แปลงวันที่
                    final date = virtualTryOn['created_at'] != null
                        ? DateFormat('dd/MM/yyyy HH:mm')
                            .format(DateTime.parse(virtualTryOn['created_at']))
                        : 'ไม่ระบุวันที่';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Virtual Try-On #${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF3B1E54),
                                  ),
                                ),
                                Text(
                                  date,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF9B7EBD),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // แสดงรูปเสื้อผ้าที่ใช้ในการ try-on
                                if (garmentId != null)
                                  FutureBuilder<Map<String, dynamic>?>(
                                    future: _garmentService
                                        .getGarmentById(garmentId),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const SizedBox(
                                          width: 80,
                                          height: 80,
                                          child: Center(
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2)),
                                        );
                                      }
                                      if (snapshot.hasData &&
                                          snapshot.data != null) {
                                        return ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(
                                            snapshot.data!['garment_image'],
                                            width: 80,
                                            height: 80,
                                            fit: BoxFit.cover,
                                          ),
                                        );
                                      }
                                      return const SizedBox(
                                        width: 80,
                                        height: 80,
                                        child: Center(
                                            child: Icon(Icons.broken_image)),
                                      );
                                    },
                                  ),
                                const SizedBox(width: 16),
                                // แสดงรูปภาพผลลัพธ์ virtual try-on
                                if (resultImage != null)
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () =>
                                          _viewVirtualTryOnResult(virtualTryOn),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          resultImage,
                                          width: 120,
                                          height: 160,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            print(
                                                'Error loading image: $error');
                                            return Container(
                                              width: 120,
                                              height: 160,
                                              color: Colors.grey.shade200,
                                              child: Center(
                                                child: Icon(
                                                  Icons.broken_image,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // เพิ่มปุ่มดูผลลัพธ์
                                TextButton.icon(
                                  onPressed: () =>
                                      _viewVirtualTryOnResult(virtualTryOn),
                                  icon: const Icon(Icons.visibility,
                                      color: Color(0xFF3B1E54)),
                                  label: const Text(
                                    'Show Result',
                                    style: TextStyle(color: Color(0xFF3B1E54)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // ปุ่มลบประวัติ
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Color(0xFFE57373)),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('ยืนยันการลบ'),
                                        content: const Text(
                                            'คุณต้องการลบประวัติการลองเสื้อผ้านี้ใช่หรือไม่?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('ยกเลิก'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _deleteVirtualTryOn(
                                                  virtualTryOn['_id']);
                                            },
                                            child: const Text('ลบ'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
