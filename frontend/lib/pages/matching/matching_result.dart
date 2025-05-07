import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitchoose/components/container_matchingresult.dart';
import 'package:fitchoose/components/pictureselect.dart';
import 'package:fitchoose/services/api_service.dart';
import 'package:fitchoose/services/garment_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http show get;

class MatchingResult extends StatefulWidget {
  // แก้ไขการประกาศพารามิเตอร์ให้ถูกต้อง
  final Map<String, dynamic>? upperGarment;
  final Map<String, dynamic>? lowerGarment;
  final String? matchingId; // เพิ่ม matchingId
  final String? matchingDetail;
  final String? matchingResult;

  const MatchingResult({
    super.key,
    this.upperGarment,
    this.lowerGarment,
    this.matchingId,
    this.matchingDetail,
    this.matchingResult,
  });

  @override
  State<MatchingResult> createState() => _MatchingResultState();
}

class _MatchingResultState extends State<MatchingResult> {
  bool isFavorite = false;

  // เพิ่มตัวแปรที่จำเป็น
  final GarmentService _garmentService = GarmentService();
  final ApiService _apiService = ApiService();
  String matchingResult = 'Vintage Style'; // ค่าเริ่มต้น
  String matchingDetail =
      'Bringing back or reinterpreting past fashion styles, such as flared jeans that were popular in the 60s and have become trendy again in the present day.'; // ค่าเริ่มต้น
  Map<String, dynamic>? upperGarment;
  Map<String, dynamic>? lowerGarment;
  List<Map<String, dynamic>> suggestedGarments = [];
  bool isLoadingSuggestions = false;
  bool isLoading = false;
  String? recommendationImageUrl;
  Map<String, dynamic>? suggestedUpperGarment;
  Map<String, dynamic>? suggestedLowerGarment;

  @override
  void initState() {
    super.initState();

    // กำหนดค่าเริ่มต้นจาก widget
    upperGarment = widget.upperGarment;
    lowerGarment = widget.lowerGarment;

    // ใช้ค่าที่ส่งมาถ้ามี
    if (widget.matchingResult != null) {
      matchingResult = widget.matchingResult!;
    }

    if (widget.matchingDetail != null) {
      matchingDetail = widget.matchingDetail!;
    }

    // ตรวจสอบสถานะ favorite
    _checkFavoriteStatus();

    // ถ้าไม่มีข้อมูลที่ส่งมา ให้ดึงข้อมูลจาก API
    if (widget.matchingId != null &&
        (widget.upperGarment == null ||
            widget.lowerGarment == null ||
            widget.matchingDetail == null ||
            widget.matchingResult == null)) {
      _loadMatchingDetails();
    }

    // โหลดเสื้อผ้าที่แนะนำ
    _loadSuggestedGarments();
  }

// เพิ่มเมธอดสำหรับโหลดเสื้อผ้าที่แนะนำ
  Future<void> _loadSuggestedGarments() async {
    setState(() {
      isLoading = true;
    });

    try {
      // ใช้ชื่อสไตล์จาก matchingResult เพื่อขอคำแนะนำ
      final style = matchingResult.split(' ')[0].toLowerCase();

      // เรียกใช้ API เพื่อขอคำแนะนำเสื้อผ้า
      try {
        final upperResponse = await http.get(
          Uri.parse(
              '${_apiService.baseUrl}/suggest_garments?category=$style&garment_type=upper'),
        );

        if (upperResponse.statusCode == 200) {
          final upperData = jsonDecode(upperResponse.body);
          setState(() {
            suggestedUpperGarment =
                upperData is List ? upperData.first : upperData;
          });
        }
      } catch (e) {
        print('Error loading suggested upper garments: $e');
      }

      try {
        final lowerResponse = await http.get(
          Uri.parse(
              '${_apiService.baseUrl}/suggest_garments?category=$style&garment_type=lower'),
        );

        if (lowerResponse.statusCode == 200) {
          final lowerData = jsonDecode(lowerResponse.body);
          setState(() {
            suggestedLowerGarment =
                lowerData is List ? lowerData.first : lowerData;
          });
        }
      } catch (e) {
        print('Error loading suggested lower garments: $e');
      }
    } catch (e) {
      print('Error loading suggested garments: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // เพิ่มเมธอดสำหรับตรวจสอบสถานะ favorite
  Future<void> _checkFavoriteStatus() async {
    if (widget.matchingId != null) {
      try {
        final favorites = await _garmentService.getFavorites();
        final isFav = favorites.any((fav) => fav['_id'] == widget.matchingId);
        setState(() {
          isFavorite = isFav;
        });
      } catch (e) {
        print('Error checking favorite status: $e');
      }
    }
  }

  Future<void> _loadMatchingDetails() async {
    try {
      // ดึงข้อมูล matching จาก API
      final matchingData =
          await _garmentService.getMatchingById(widget.matchingId!);

      setState(() {
        matchingResult = matchingData['matching_result'] ?? 'Unknown Style';
        matchingDetail = matchingData['matching_detail'] ?? '';

        // ดึงข้อมูลเสื้อผ้าถ้ายังไม่มี
        if (widget.upperGarment == null &&
            matchingData['garment_top'] != null) {
          _loadUpperGarment(matchingData['garment_top']);
        }

        if (widget.lowerGarment == null &&
            matchingData['garment_bottom'] != null) {
          _loadLowerGarment(matchingData['garment_bottom']);
        }
      });
    } catch (e) {
      print('Error loading matching details: $e');
    }
  }

// เพิ่มเมธอดสำหรับโหลดข้อมูลเสื้อผ้าส่วนบน
  Future<void> _loadUpperGarment(String garmentId) async {
    try {
      final garmentData = await _garmentService.getGarmentById(garmentId);
      if (garmentData != null) {
        setState(() {
          upperGarment = garmentData;
        });
      }
    } catch (e) {
      print('Error loading upper garment: $e');
    }
  }

  // เพิ่มเมธอดสำหรับโหลดข้อมูลเสื้อผ้าส่วนล่าง
  Future<void> _loadLowerGarment(String garmentId) async {
    try {
      final garmentData = await _garmentService.getGarmentById(garmentId);
      if (garmentData != null) {
        setState(() {
          lowerGarment = garmentData;
        });
      }
    } catch (e) {
      print('Error loading lower garment: $e');
    }
  }

  // ในส่วนของการแสดงผล
  Widget _buildSuggestedGarments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'แนะนำเสื้อผ้าที่เข้ากัน',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3B1E54),
          ),
        ),
        const SizedBox(height: 16),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (suggestedUpperGarment != null || suggestedLowerGarment != null)
          Column(
            children: [
              if (suggestedUpperGarment != null)
                _buildSuggestedGarmentCard(
                  suggestedUpperGarment!['category'],
                  suggestedUpperGarment!['description'],
                  '${_apiService.baseUrl}${suggestedUpperGarment!['image_url']}',
                ),
              if (suggestedLowerGarment != null)
                _buildSuggestedGarmentCard(
                  suggestedLowerGarment!['category'],
                  suggestedLowerGarment!['description'],
                  '${_apiService.baseUrl}${suggestedLowerGarment!['image_url']}',
                ),
            ],
          )
        else
          const Center(child: Text('ไม่มีรูปภาพแนะนำ')),
      ],
    );
  }

  // เพิ่มฟังก์ชันสำหรับสร้าง card แสดงเสื้อผ้าที่แนะนำ
  Widget _buildSuggestedGarmentCard(
      String category, String description, String imageUrl) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // รูปภาพเสื้อผ้า
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            // รายละเอียดเสื้อผ้า
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3B1E54),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ตรวจสอบว่ามีเสื้อผ้าที่เลือกหรือไม่
    String? upperImageUrl = widget.upperGarment?['garment_image'];
    String? lowerImageUrl = widget.lowerGarment?['garment_image'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        title: const Text(
          'Matching +',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3B1E54),
          ),
        ),
        backgroundColor: const Color(0xFFF5F0FF),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Matching Result',
                    style: TextStyle(
                      fontSize: 20,
                      color: Color(0xFF9B7EBD),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 36),
                  // แสดงรูปเสื้อผ้าที่เลือก
                  if (upperImageUrl != null)
                    Center(
                      child: PictureSelect(
                        imageUrl: upperImageUrl,
                        width: 160,
                        height: 160,
                      ),
                    ),
                  if (lowerImageUrl != null)
                    Center(
                      child: PictureSelect(
                        imageUrl: lowerImageUrl,
                        width: 160,
                        height: 160,
                      ),
                    ),
                  // ถ้าไม่มีรูปเสื้อผ้าที่เลือก ให้แสดงรูปเดิม
                  if (upperImageUrl == null && lowerImageUrl == null)
                    Center(
                      child: PictureSelect(
                        imageUrl: 'assets/images/test.png',
                        width: 160,
                        height: 160,
                      ),
                    ),
                  SizedBox(height: 36),
                  StyleDescriptionCard(
                    title: matchingResult,
                    description: matchingDetail,
                    isFavorite: isFavorite,
                    onFavoriteTap: () async {
                      if (widget.matchingId != null) {
                        bool success;
                        if (isFavorite) {
                          success = await _garmentService
                              .removeFromFavorites(widget.matchingId!);
                        } else {
                          success = await _garmentService
                              .addToFavorites(widget.matchingId!);
                        }

                        if (success) {
                          setState(() {
                            isFavorite = !isFavorite;
                          });
                        }
                      }
                    },
                  ),
                  // แสดงรูปภาพแนะนำ
                  const SizedBox(height: 36),
                  _buildSuggestedGarments(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
