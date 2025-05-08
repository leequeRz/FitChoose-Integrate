import 'dart:convert';

import 'package:fitchoose/pages/matching/favorites_page.dart';
import 'package:fitchoose/pages/matching/history_matching_page.dart';
import 'package:fitchoose/pages/matching/matching_result.dart';
import 'package:fitchoose/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:fitchoose/services/garment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class MatchingPage extends StatefulWidget {
  const MatchingPage({super.key});

  @override
  State<MatchingPage> createState() => _MatchingPageState();
}

class _MatchingPageState extends State<MatchingPage> {
  final GarmentService _garmentService = GarmentService();
  final ApiService _apiService = ApiService();

  // เพิ่มตัวแปรเก็บเสื้อผ้าที่เลือก
  Map<String, dynamic>? selectedUpperGarment;
  Map<String, dynamic>? selectedLowerGarment;

  // เพิ่มตัวแปรเก็บรายการเสื้อผ้า
  List<Map<String, dynamic>> upperGarments = [];
  List<Map<String, dynamic>> lowerGarments = [];
  bool isLoading = false;

  bool _isAnalyzing = false;
  bool _isUpperAnalyzed = false;
  bool _isLowerAnalyzed = false;
  String? upperCategory;
  String? lowerCategory;

  @override
  void initState() {
    super.initState();
    _loadGarments();
  }

  // เพิ่มฟังก์ชัน dispose เพื่อล้างค่าเมื่อออกจากหน้า
  @override
  void dispose() {
    // ล้างค่าตัวแปรเมื่อออกจากหน้า
    selectedUpperGarment = null;
    selectedLowerGarment = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // รีเซ็ตการเลือกเสื้อผ้าเมื่อหน้าถูกแสดงอีกครั้ง
    _resetSelection();

    // โหลดข้อมูลเสื้อผ้าใหม่เมื่อกลับมาที่หน้านี้
    _loadGarments();
  }

  // เพิ่มฟังก์ชันรีเซ็ตการเลือกเสื้อผ้า
  void _resetSelection() {
    setState(() {
      selectedUpperGarment = null;
      selectedLowerGarment = null;
      upperCategory = null;
      lowerCategory = null;
    });
  }

  // เพิ่มฟังก์ชันสำหรับวิเคราะห์หมวดหมู่เสื้อผ้า
  Future<String> _classifyGarment(String garmentId, String garmentType) async {
    try {
      return await _garmentService.classifyGarment(garmentId, garmentType);
    } catch (e) {
      print('Error classifying garment: $e');
      return 'Unknown';
    }
  }

  // เพิ่มฟังก์ชันโหลดเสื้อผ้าจาก Wardrobe
  Future<void> _loadGarments() async {
    setState(() {
      isLoading = true;
      // รีเซ็ตการเลือกเสื้อผ้าเมื่อโหลดข้อมูลใหม่
      selectedUpperGarment = null;
      selectedLowerGarment = null;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // ดึงข้อมูลเสื้อผ้าแต่ละประเภท
        final uppers = await _garmentService.getGarmentsByType('upper');
        final lowers = await _garmentService.getGarmentsByType('lower');

        setState(() {
          upperGarments = uppers;
          lowerGarments = lowers;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading garments: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  // เพิ่มฟังก์ชันเปิด dialog เลือกเสื้อผ้าส่วนบน
  void _selectUpperGarment(Map<String, dynamic> garment) async {
    setState(() {
      selectedUpperGarment = garment;
      _isUpperAnalyzed = false;
      _isAnalyzing = true;
      // รีเซ็ตหมวดหมู่เพื่อรอการวิเคราะห์ใหม่
      upperCategory = null;
    });

    // แสดง popup กำลังประมวลผล
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B7EBD)),
              ),
              SizedBox(height: 16),
              Text(
                'กำลังวิเคราะห์เสื้อผ้า...',
                style: TextStyle(color: Color(0xFF9B7EBD)),
              ),
            ],
          ),
        );
      },
    );

    // วิเคราะห์เสื้อผ้า
    try {
      final response = await http.post(
        Uri.parse('${_apiService.baseUrl}/classify_garment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'garment_id': garment['_id'],
          'garment_type': 'upper',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          upperCategory = data['category'];
          _isUpperAnalyzed = true;
          _isAnalyzing = _isLowerAnalyzed ? false : _isAnalyzing;
        });
        print('Upper category: $upperCategory');
      } else {
        print('Error classifying upper garment: ${response.body}');
      }
    } catch (e) {
      print('Exception classifying upper garment: $e');
    } finally {
      // ปิด popup
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  // เพิ่มฟังก์ชันเปิด dialog เลือกเสื้อผ้าส่วนล่าง
  void _selectLowerGarment(Map<String, dynamic> garment) async {
    setState(() {
      selectedLowerGarment = garment;
      _isLowerAnalyzed = false;
      _isAnalyzing = true;
      // รีเซ็ตหมวดหมู่เพื่อรอการวิเคราะห์ใหม่
      lowerCategory = null;
    });

    // แสดง popup กำลังประมวลผล
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B7EBD)),
              ),
              SizedBox(height: 16),
              Text(
                'กำลังวิเคราะห์เสื้อผ้า...',
                style: TextStyle(color: Color(0xFF9B7EBD)),
              ),
            ],
          ),
        );
      },
    );

    // วิเคราะห์เสื้อผ้า
    try {
      final response = await http.post(
        Uri.parse('${_apiService.baseUrl}/classify_garment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'garment_id': garment['_id'],
          'garment_type': 'lower',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          lowerCategory = data['category'];
          _isLowerAnalyzed = true;
          _isAnalyzing = _isUpperAnalyzed ? false : _isAnalyzing;
        });
        print('Lower category: $lowerCategory');
      } else {
        print('Error classifying lower garment: ${response.body}');
      }
    } catch (e) {
      print('Exception classifying lower garment: $e');
    } finally {
      // ปิด popup
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  // เพิ่มฟังก์ชันสำหรับแสดง dialog เลือกเสื้อผ้าส่วนบน
  void _showUpperGarmentSelector() async {
    // โหลดข้อมูลเสื้อผ้าใหม่ก่อนแสดง dialog
    await _loadGarments();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select your upper garments',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3B1E54)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : upperGarments.isEmpty
                      ? const Center(child: Text('ไม่พบเสื้อผ้าส่วนบน'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: upperGarments.length,
                          itemBuilder: (context, index) {
                            final garment = upperGarments[index];
                            return GestureDetector(
                              onTap: () {
                                _selectUpperGarment(garment);
                                Navigator.pop(context);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(10),
                                          topRight: Radius.circular(10),
                                        ),
                                        child: Image.network(
                                          garment['garment_image'],
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                            Icons.broken_image,
                                            size: 50,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Padding(
                                    //   padding: const EdgeInsets.all(8.0),
                                    //   child: Text(
                                    //     garment['garment_name'] ?? 'ไม่มีชื่อ',
                                    //     style: const TextStyle(
                                    //       fontSize: 14,
                                    //       fontWeight: FontWeight.bold,
                                    //     ),
                                    //     maxLines: 1,
                                    //     overflow: TextOverflow.ellipsis,
                                    //   ),
                                    // ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // เพิ่มฟังก์ชันสำหรับแสดง dialog เลือกเสื้อผ้าส่วนล่าง
  void _showLowerGarmentSelector() async {
    // โหลดข้อมูลเสื้อผ้าใหม่ก่อนแสดง dialog
    await _loadGarments();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select your lower garments',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3B1E54),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : lowerGarments.isEmpty
                      ? const Center(child: Text('ไม่พบเสื้อผ้าส่วนล่าง'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.75,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: lowerGarments.length,
                          itemBuilder: (context, index) {
                            final garment = lowerGarments[index];
                            return GestureDetector(
                              onTap: () {
                                _selectLowerGarment(garment);
                                Navigator.pop(context);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(10),
                                          topRight: Radius.circular(10),
                                        ),
                                        child: Image.network(
                                          garment['garment_image'],
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                            Icons.broken_image,
                                            size: 50,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Padding(
                                    //   padding: const EdgeInsets.all(8.0),
                                    //   child: Text(
                                    //     garment['garment_name'] ?? 'ไม่มีชื่อ',
                                    //     style: const TextStyle(
                                    //       fontSize: 14,
                                    //       fontWeight: FontWeight.bold,
                                    //     ),
                                    //     maxLines: 1,
                                    //     overflow: TextOverflow.ellipsis,
                                    //   ),
                                    // ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      body: SafeArea(
        child: Padding(
          // ลดขนาด padding ด้านข้างลงเพื่อแก้ปัญหา overflow ด้านขวา
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with title and buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ลดขนาดตัวอักษรของหัวข้อลงเล็กน้อย
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Matching +',
                          style: TextStyle(
                            fontSize: 32, // ลดจาก 32
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B1E54),
                          ),
                        ),
                        Text(
                          'Matching Your Outfits',
                          style: TextStyle(
                            fontSize: 18, // ลดจาก 18
                            color: Color(0xFF9B7EBD),
                          ),
                        ),
                      ],
                    ),
                    // ปรับขนาดและระยะห่างของปุ่ม
                    Row(
                      children: [
                        // Reset button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedUpperGarment = null;
                              selectedLowerGarment = null;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Selection reset successfully'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6), // ลดจาก 8
                            margin: const EdgeInsets.only(right: 8), // ลดจาก 12
                            decoration: BoxDecoration(
                              color: const Color(0xFF9B7EBD).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.refresh_rounded,
                              color: Color(0xFF9B7EBD),
                              size: 24, // ลดจาก 28
                            ),
                          ),
                        ),
                        // History button
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HistoryMatchingPage(),
                              ),
                            ).then((_) {
                              _resetSelection();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6), // ลดจาก 8
                            margin: const EdgeInsets.only(right: 8), // ลดจาก 12
                            decoration: BoxDecoration(
                              color: const Color(0xFF9B7EBD).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              color: Color(0xFF9B7EBD),
                              size: 24, // ลดจาก 28
                            ),
                          ),
                        ),
                        // Heart button
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => FavoritesPage()),
                            ).then((_) {
                              _resetSelection();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6), // ลดจาก 8
                            decoration: BoxDecoration(
                              color: const Color(0xFF9B7EBD).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFF9B7EBD),
                              size: 24, // ลดจาก 28
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // แก้ไข GestureDetector สำหรับเลือกเสื้อผ้าส่วนบน
                GestureDetector(
                  onTap: () {
                    _showUpperGarmentSelector();
                  },
                  child: Center(
                    child: Container(
                      width: 230,
                      // ลดความสูงลงเล็กน้อย
                      height: 170,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4BEE4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: selectedUpperGarment == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'Select Your',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Upper-Body',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                )
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.network(
                                selectedUpperGarment!['garment_image'],
                                width: 230,
                                height: 170,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                  Icons.broken_image,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16), // ลดระยะห่างลง
                const Center(
                  child: Text('OR',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16), // ลดระยะห่างลง
                // แก้ไข GestureDetector สำหรับเลือกเสื้อผ้าส่วนล่าง
                GestureDetector(
                  onTap: () {
                    _showLowerGarmentSelector();
                  },
                  child: Center(
                    child: Container(
                      width: 230,
                      // ลดความสูงลงเล็กน้อย
                      height: 170,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4BEE4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: selectedLowerGarment == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'Select Your',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Lower-Body',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                )
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.network(
                                selectedLowerGarment!['garment_image'],
                                width: 230,
                                height: 170,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                  Icons.broken_image,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                // ลดระยะห่างด้านบนของปุ่ม Matching
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(
                        top: 30, bottom: 20), // เพิ่ม margin ด้านล่าง
                    width: 200,
                    height: 50, // ลดความสูงของปุ่ม
                    //ปุ่ม matching
                    child: ElevatedButton(
                      onPressed: () async {
                        // ตรวจสอบว่ามีการเลือกเสื้อผ้าอย่างน้อย 1 ชิ้น
                        if (selectedUpperGarment == null &&
                            selectedLowerGarment == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Please select at least one garment')),
                          );
                          return;
                        }

                        // บันทึกประวัติการทำ matching
                        try {
                          final userId = FirebaseAuth.instance.currentUser?.uid;
                          if (userId != null) {
                            // แสดง loading indicator
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF9B7EBD)),
                              ),
                            );

                            // สร้างข้อมูล matching
                            final matchingData = {
                              'user_id': userId,
                              'garment_top': selectedUpperGarment?['_id'],
                              'garment_bottom': selectedLowerGarment?['_id'],
                              'matching_date': DateTime.now().toIso8601String(),
                              'matching_result':
                                  _garmentService.getStyleNameFromCategories(
                                      upperCategory ?? 'Unknown',
                                      lowerCategory ?? 'Unknown'),
                              'matching_detail': _garmentService
                                  .getCategoryDescription(upperCategory ??
                                      lowerCategory ??
                                      'Unknown'), // เพิ่ม matching_detail
                              'is_favorite':
                                  false, // เพิ่ม is_favorite เป็นค่าเริ่มต้น
                              'upper_category': upperCategory ?? 'Unknown',
                              'lower_category': lowerCategory ?? 'Unknown',
                            };

                            print('Sending matching data: $matchingData');

                            // บันทึกข้อมูล matching
                            final response = await _garmentService
                                .saveMatching(matchingData);

                            // ปิด loading indicator
                            Navigator.pop(context);

                            print('Received response: $response');

                            // ตรวจสอบและดึง matchingId จาก response
                            String matchingId;
                            if (response != null) {
                              if (response.containsKey('_id')) {
                                matchingId = response['_id'];

                                // สร้างชื่อสไตล์และคำอธิบายจากหมวดหมู่
                                final styleName =
                                    _garmentService.getStyleNameFromCategories(
                                        upperCategory ?? 'Unknown',
                                        lowerCategory ?? 'Unknown');

                                final styleDescription = _garmentService
                                    .getCategoryDescription(upperCategory ??
                                        lowerCategory ??
                                        'Unknown');

                                // อัปเดตข้อมูล matching ด้วยชื่อสไตล์และคำอธิบาย
                                await _garmentService.updateMatchingDetail(
                                    matchingId, styleDescription);

                                // ส่งข้อมูลเสื้อผ้าที่เลือกไปยังหน้า MatchingResult
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => MatchingResult(
                                      upperGarment: selectedUpperGarment,
                                      lowerGarment: selectedLowerGarment,
                                      matchingId: matchingId,
                                      matchingResult: styleName,
                                      matchingDetail: styleDescription,
                                    ),
                                  ),
                                ).then((_) {
                                  // เมื่อกลับมาจากหน้า MatchingResult ให้รีเซ็ตการเลือกเสื้อผ้า
                                  setState(() {
                                    selectedUpperGarment = null;
                                    selectedLowerGarment = null;
                                    upperCategory = null;
                                    lowerCategory = null;
                                  });
                                });
                              }
                            } else {
                              // กรณีไม่ได้ล็อกอิน
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Please login to use matching feature'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          } else {
                            // กรณีไม่ได้ล็อกอิน
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Please login to use matching feature'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (e) {
                          print('Error saving matching history: $e');
                          // ปิด loading indicator ถ้ายังแสดงอยู่
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);

                          // แสดงข้อความแจ้งเตือน
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              duration: const Duration(seconds: 2),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9B7EBD),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 12, // ลดระยะห่างแนวตั้ง
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        'Matching',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
