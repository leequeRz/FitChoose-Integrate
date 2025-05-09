import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitchoose/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MatchingResultPage extends StatefulWidget {
  final Map<String, dynamic> matchingResult;
  final Map<String, dynamic> upperGarment;
  final Map<String, dynamic> lowerGarment;
  final String upperCategory;
  final String lowerCategory;

  const MatchingResultPage({
    Key? key,
    required this.matchingResult,
    required this.upperGarment,
    required this.lowerGarment,
    required this.upperCategory,
    required this.lowerCategory,
  }) : super(key: key);

  @override
  State<MatchingResultPage> createState() => _MatchingResultPageState();
}

class _MatchingResultPageState extends State<MatchingResultPage> {
  final ApiService _apiService = ApiService();
  bool _isSaving = false;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkIfFavorite();
  }

  // ตรวจสอบว่าการจับคู่นี้เป็นรายการโปรดหรือไม่
  Future<void> _checkIfFavorite() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final response = await http.get(
        Uri.parse(
            '${_apiService.baseUrl}/check_favorite?user_id=$userId&upper_garment_id=${widget.upperGarment['_id']}&lower_garment_id=${widget.lowerGarment['_id']}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isFavorite = data['is_favorite'] ?? false;
        });
      }
    } catch (e) {
      print('Error checking favorite: $e');
    }
  }

  // บันทึกการจับคู่เป็นรายการโปรด
  Future<void> _toggleFavorite() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw Exception('ไม่พบข้อมูลผู้ใช้');
      }

      final endpoint = _isFavorite
          ? '${_apiService.baseUrl}/remove_favorite'
          : '${_apiService.baseUrl}/add_favorite';

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'upper_garment_id': widget.upperGarment['_id'],
          'lower_garment_id': widget.lowerGarment['_id'],
          'upper_category': widget.upperCategory,
          'lower_category': widget.lowerCategory,
          'matching_score': widget.matchingResult['matching_score'] ?? 0,
          'matching_details': widget.matchingResult['matching_details'] ?? {},
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _isFavorite = !_isFavorite;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFavorite ? 'เพิ่มในรายการโปรดแล้ว' : 'ลบออกจากรายการโปรดแล้ว'),
            backgroundColor: Color(0xFF9B7EBD),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: ${response.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error toggling favorite: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchingScore = widget.matchingResult['matching_score'] ?? 0;
    final matchingDetails = widget.matchingResult['matching_details'] ?? {};
    final recommendations = widget.matchingResult['recommendations'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ผลการจับคู่',
          style: TextStyle(
            color: Color(0xFF3B1E54),
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3B1E54)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : Color(0xFF3B1E54),
            ),
            onPressed: _isSaving ? null : _toggleFavorite,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // แสดงรูปภาพเสื้อผ้าที่เลือก
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // เสื้อผ้าส่วนบน
                Column(
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          widget.upperGarment['garment_image'],
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
                    const SizedBox(height: 8),
                    Text(
                      'ประเภท: ${widget.upperCategory}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3B1E54),
                      ),
                    ),
                  ],
                ),
                // เสื้อผ้าส่วนล่าง
                Column(
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          widget.lowerGarment['garment_image'],
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
                    const SizedBox(height: 8),
                    Text(
                      'ประเภท: ${widget.lowerCategory}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3B1E54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // แสดงคะแนนการจับคู่
            Center(
              child: Column(
                children: [
                  Text(
                    'คะแนนการจับคู่',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3B1E54),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getScoreColor(matchingScore),
                    ),
                    child: Center(
                      child: Text(
                        '${(matchingScore * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // แสดงรายละเอียดการจับคู่
            Text(
              'รายละเอียดการจับคู่',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3B1E54),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (matchingDetails.containsKey('color_matching'))
                      _buildDetailItem(
                        'การจับคู่สี',
                        matchingDetails['color_matching'] ?? 0,
                      ),
                    if (matchingDetails.containsKey('style_matching'))
                      _buildDetailItem(
                        'การจับคู่สไตล์',
                        matchingDetails['style_matching'] ?? 0,
                      ),
                    if (matchingDetails.containsKey('occasion_matching'))
                      _buildDetailItem(
                        'ความเหมาะสมกับโอกาส',
                        matchingDetails['occasion_matching'] ?? 0,
                      ),
                    if (matchingDetails.containsKey('season_matching'))
                      _buildDetailItem(
                        'ความเหมาะสมกับฤดูกาล',
                        matchingDetails['season_matching'] ?? 0,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // แสดงคำแนะนำ
            if (recommendations.isNotEmpty) ...[
              Text(
                'คำแนะนำ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B1E54),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var recommendation in recommendations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: Color(0xFF9B7EBD),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  recommendation,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF3B1E54),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // สร้าง widget สำหรับแสดงรายละเอียดแต่ละรายการ
  Widget _buildDetailItem(String title, double score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3B1E54),
            ),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: score,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(score)),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 4),
          Text(
            '${(score * 100).toInt()}%',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF3B1E54),
            ),
          ),
        ],
      ),
    );
  }

  // กำหนดสีตามคะแนน
  Color _getScoreColor(double score) {
    if (score >= 0.8) {
      return Colors.green;
    } else if (score >= 0.6) {
      return Colors.amber;
    } else if (score >= 0.4) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}