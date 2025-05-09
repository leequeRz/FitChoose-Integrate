import 'package:fitchoose/components/pictureselect.dart';
import 'package:fitchoose/pages/virtualtryon/virtual_tryon_result_page.dart';
import 'package:fitchoose/services/api_service.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:fitchoose/services/garment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:fitchoose/pages/virtualtryon/history_virtual_try_on_page.dart';

class VirtualTryOnPage extends StatefulWidget {
  const VirtualTryOnPage({super.key});

  @override
  _VirtualTryOnPageState createState() => _VirtualTryOnPageState();
}

class _VirtualTryOnPageState extends State<VirtualTryOnPage>
    with WidgetsBindingObserver {
  String? imageUrl;
  String selectedCategory = 'Upper-Body';
  bool isLoading = true;
  final apiService = ApiService();
  final GarmentService _garmentService = GarmentService();
  String userName = 'Loading...';
  String gender = 'Loading...';
  FocusNode _focusNode = FocusNode(); // เพิ่มตัวแปร FocusNode
  bool _isFirstLoad = true; // เพิ่มตัวแปรเพื่อตรวจสอบการโหลดครั้งแรก

  // เพิ่มตัวแปรสำหรับเก็บผลลัพธ์ Virtual Try-On
  File? _tryOnResultImage;
  bool _isProcessing = false;
  Map<String, dynamic>? _currentSelectedGarment; // เพิ่มตัวแปรนี้

  // เปลี่ยนโครงสร้างข้อมูลเพื่อรองรับข้อมูลจาก API
  final Map<String, List<Map<String, dynamic>>> clothingItems = {
    'Upper-Body': [],
    'Lower-Body': [],
    'Dress': [],
  };

  @override
  void initState() {
    super.initState();
    // เพิ่ม observer เพื่อตรวจจับเมื่อแอปกลับมาที่หน้านี้
    WidgetsBinding.instance.addObserver(this);
    _loadGarments();
    _loadUserProfile();
    _focusNode.addListener(_onFocusChange); // เพิ่ม listener
  }

  @override
  void dispose() {
    // ลบ observer เมื่อออกจากหน้านี้
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChange); // ลบ listener
    _focusNode.dispose(); // ทำลาย FocusNode
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // เมื่อหน้านี้ได้รับ focus
      _loadUserProfile();
    }
  }

  // เพิ่มฟังก์ชันเพื่อตรวจจับเมื่อแอปกลับมาที่หน้านี้
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isFirstLoad) {
      // ไม่ใช่การโหลดครั้งแรก ให้โหลดข้อมูลโปรไฟล์ใหม่
      _loadUserProfile();
    }
    _isFirstLoad = false;
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userId = user.uid;
        print('Fetching profile for user: $userId');

        // เรียกใช้ API เพื่อดึงข้อมูลผู้ใช้
        final response = await apiService.checkUserExists(userId);

        if (response['exists'] == true && response.containsKey('user_data')) {
          final userData = response['user_data'];
          setState(() {
            userName = userData['username'] ?? 'No Name';
            gender = userData['gender'] ?? 'Not Specified';
            imageUrl = userData['image_url'];
            isLoading = false;
          });
          print('Profile loaded: $userName, $gender');
        } else {
          print('User profile not found');
          setState(() {
            userName = 'Profile Not Found';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading profile: $e');
      setState(() {
        userName = 'Error Loading Profile';
        isLoading = false;
      });
    }
  }

  // เพิ่มฟังก์ชันสำหรับโหลดข้อมูลเสื้อผ้า
  Future<void> _loadGarments() async {
    setState(() {
      isLoading = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // ดึงข้อมูลเสื้อผ้าแต่ละประเภท
        final upperGarments = await _garmentService.getGarmentsByType('upper');
        final lowerGarments = await _garmentService.getGarmentsByType('lower');
        final dressGarments = await _garmentService.getGarmentsByType('dress');

        // ตรวจสอบว่าหน้านี้ยังคงอยู่ในสแต็ค (ป้องกันการเรียก setState หลังจาก dispose)
        if (mounted) {
          setState(() {
            clothingItems['Upper-Body'] = upperGarments;
            clothingItems['Lower-Body'] = lowerGarments;
            clothingItems['Dress'] = dressGarments;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading garments: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // เพิ่มเมธอดสำหรับทำ Virtual Try-On
  Future<void> _performVirtualTryOn(
      Map<String, dynamic> selectedGarment) async {
    if (imageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาอัปโหลดรูปโปรไฟล์ก่อน')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // ดาวน์โหลดรูปโปรไฟล์
      final response = await http.get(Uri.parse(imageUrl!));
      if (response.statusCode != 200) {
        throw Exception('Failed to download profile image');
      }

      // สร้างไฟล์ชั่วคราวสำหรับรูปโปรไฟล์
      final tempDir = await getTemporaryDirectory();
      final humanImageFile = File('${tempDir.path}/profile.jpg');
      await humanImageFile.writeAsBytes(response.bodyBytes);

      // แปลงประเภทเสื้อผ้าให้ตรงกับที่ backend ต้องการ
      String garmentType = selectedCategory.toLowerCase();
      if (selectedCategory == 'Upper-Body') {
        garmentType = 'upper';
      } else if (selectedCategory == 'Lower-Body') {
        garmentType = 'lower';
      } else if (selectedCategory == 'Dress') {
        garmentType = 'dress';
      }

      // ทำ Virtual Try-On
      final resultPath = await _garmentService.performVirtualTryOn(
        humanImage: humanImageFile,
        garmentImageUrl: selectedGarment['garment_image'],
        category: selectedCategory,
        // orientation: "portrait",
      );

      if (resultPath != null) {
        // บันทึกผลลัพธ์
        await _garmentService.saveVirtualTryOnResult(
          garmentId: selectedGarment['_id'],
          garmentType: garmentType,
          resultImagePath: resultPath,
        );

        setState(() {
          _tryOnResultImage = File(resultPath);
          _isProcessing = false;
          _currentSelectedGarment =
              selectedGarment; // เก็บข้อมูลเสื้อผ้าที่เลือก
        });

        // แสดงผลลัพธ์ Virtual Try-On
        // _showTryOnResult();

        // แทนที่จะเรียก _showTryOnResult() ให้นำทางไปยังหน้าใหม่
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VirtualTryOnResultPage(
              resultImage: _tryOnResultImage!,
              selectedGarment: _currentSelectedGarment!,
              category: selectedCategory,
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Virtual Try-On สำเร็จ!')),
        );
      } else {
        throw Exception('Failed to perform virtual try-on');
      }
    } catch (e) {
      print('Error in _performVirtualTryOn: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: ${e.toString()}')),
      );
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // แก้ไขฟังก์ชัน _buildClothingGrid
  Widget _buildClothingGrid() {
    final items = clothingItems[selectedCategory] ?? [];

    if (items.isEmpty) {
      return Center(
        child: Text(
          'ไม่พบเสื้อผ้าในหมวดหมู่นี้',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF9B7EBD),
          ),
        ),
      );
    }

    // เปลี่ยนจาก GridView เป็น ListView แนวนอน
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final imageUrl = item['garment_image'] ?? '';

          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                // เรียกใช้ฟังก์ชัน Virtual Try-On เมื่อคลิกที่รูปภาพ
                _performVirtualTryOn(item);
              },
              child: Container(
                width: 180,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.fill,
                    width: double.infinity,
                    height: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: Color(0xFF9B7EBD),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 32,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // เพิ่มฟังก์ชันเพื่อรีเฟรชข้อมูลเมื่อกดปุ่ม
  Future<void> _refreshData() async {
    await _loadGarments();
    await _loadUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F0FF), // Light purple background
        body: Stack(
          children: [
            SafeArea(
              child:
                  // เนื้อหาหลัก
                  Padding(
                padding: const EdgeInsets.all(24.0),
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ส่วนหัวข้อด้านซ้าย
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Virtual Try-on',
                                    style: TextStyle(
                                      fontSize: 32, // ลดขนาดจาก 32
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3B1E54), // Deep purple
                                    ),
                                  ),
                                  Text(
                                    'Customize your outfit effortlessly',
                                    style: TextStyle(
                                      fontSize: 16, // ลดขนาดจาก 18
                                      color: Color(0xFF9B7EBD), // Medium purple
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // ปุ่มด้านขวา - ใช้รูปแบบเดียวกับหน้า Matching
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  icon: Icon(
                                    Icons.history_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'History',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF9B7EBD),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const HistoryVirtualTryOnPage(),
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(width: 8),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: PictureSelect(
                            imageUrl: imageUrl ?? 'assets/images/test.png',
                            width: 230,
                            height: 300,
                          ),
                        ),
                        SizedBox(height: 24),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (String category in [
                                'Upper-Body',
                                'Lower-Body',
                                'Dress'
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: CategoryButton(
                                    text: category,
                                    isSelected: selectedCategory == category,
                                    onTap: () {
                                      setState(() {
                                        selectedCategory = category;
                                      });
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedCategory,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B1E54),
                              ),
                            ),
                            SizedBox(height: 25),
                            isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                        color: Color(0xFF9B7EBD)))
                                : _buildClothingGrid(),
                          ],
                        ),
                        SizedBox(height: 25)
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // แสดงตัวบ่งชี้การประมวลผลเมื่อกำลังทำ Virtual Try-On
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.white,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'กำลังประมวลผล Virtual Try-On...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Category Button Widget
class CategoryButton extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryButton({
    Key? key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6D8F5) : Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          text,
          style: TextStyle(
            color:
                isSelected ? const Color(0xFF9B7EBD) : const Color(0xFFCBB6E5),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// Clothing Item Card Widget - ปรับเพื่อรองรับ URL แทน asset path และเพิ่มพารามิเตอร์ width, height
class ClothingItemCard extends StatelessWidget {
  final String imageUrl;
  final VoidCallback? onDeleteTap;
  final double width;
  final double height;

  const ClothingItemCard({
    Key? key,
    required this.imageUrl,
    this.onDeleteTap,
    this.width = double.infinity,
    this.height = double.infinity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F1FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEAE2F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 180,
                height: 240,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 50,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
