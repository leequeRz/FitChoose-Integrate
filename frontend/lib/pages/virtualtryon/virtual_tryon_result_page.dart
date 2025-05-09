import 'package:flutter/material.dart';
import 'dart:io';

class VirtualTryOnResultPage extends StatefulWidget {
  final File resultImage;
  final Map<String, dynamic> selectedGarment;
  final String category;

  const VirtualTryOnResultPage({
    Key? key,
    required this.resultImage,
    required this.selectedGarment,
    required this.category,
  }) : super(key: key);

  @override
  State<VirtualTryOnResultPage> createState() => _VirtualTryOnResultPageState();
}

class _VirtualTryOnResultPageState extends State<VirtualTryOnResultPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Result Virtual Try-On'),
        backgroundColor: Color(0xFF3B1E54),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F0FF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ส่วนแสดงข้อมูลเสื้อผ้าที่เลือก
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            widget.selectedGarment['garment_image'] ?? '',
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
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
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Garment:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3B1E54),
                                ),
                              ),
                              SizedBox(height: 8),
                              // Text(
                              //   selectedGarment['garment_name'] ?? 'ไม่มีชื่อ',
                              //   style: TextStyle(
                              //     fontSize: 16,
                              //     color: Color(0xFF9B7EBD),
                              //   ),
                              // ),
                              SizedBox(height: 4),
                              Text(
                                'Type: ${widget.category}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF9B7EBD),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // ส่วนแสดงผลลัพธ์
                Text(
                  'This is the result:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3B1E54),
                  ),
                ),

                SizedBox(height: 16),

                // แสดงรูปภาพผลลัพธ์
                Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width,
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        widget.resultImage,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // ปุ่มบันทึกรูปภาพ
                // Center(
                //   child: ElevatedButton.icon(
                //     onPressed: _saveImage,
                //     style: ElevatedButton.styleFrom(
                //       backgroundColor: Color(0xFF3B1E54),
                //       padding:
                //           EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                //       shape: RoundedRectangleBorder(
                //         borderRadius: BorderRadius.circular(8),
                //       ),
                //     ),
                //     icon: Icon(Icons.save_alt),
                //     label: Text(
                //       'Save image',
                //       style: TextStyle(fontSize: 16),
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
