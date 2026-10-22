import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database.dart';
import '../models/document_struct.dart';

/// Widget bản đồ tương tác đa nền tảng (Web, Android, iOS)
/// Hỗ trợ cả chế độ xem (View mode) và chế độ chọn vị trí (Picker mode)
class DocumentMapWidget extends StatefulWidget {
  const DocumentMapWidget({
    super.key,
    this.documents = const [],
    this.selectedDocument,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
    this.isPicker = false,
    this.onLocationChanged,
    this.height,
  });

  final List<Document> documents;
  final Document? selectedDocument;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;
  final bool isPicker;
  final void Function(double lat, double lng, String address)? onLocationChanged;
  final double? height;

  @override
  State<DocumentMapWidget> createState() => _DocumentMapWidgetState();
}

class _DocumentMapWidgetState extends State<DocumentMapWidget> {
  // Tọa độ mặc định tại Trường Đại học Thủy Lợi (175 Tây Sơn, Đống Đa, Hà Nội)
  static const double defaultLat = 21.0074;
  static const double defaultLng = 105.8248;

  late double _currentLat;
  late double _currentLng;
  late String _currentAddress;
  double _zoomLevel = 16.0;
  Document? _activeDocument;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLatitude ??
        widget.selectedDocument?.latitude ??
        defaultLat;
    _currentLng = widget.initialLongitude ??
        widget.selectedDocument?.longitude ??
        defaultLng;
    _currentAddress = widget.initialAddress ??
        widget.selectedDocument?.physicalAddress ??
        'Đại học Thủy Lợi, 175 Tây Sơn, Hà Nội';
    _activeDocument = widget.selectedDocument;
  }

  @override
  void didUpdateWidget(covariant DocumentMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDocument != oldWidget.selectedDocument &&
        widget.selectedDocument != null) {
      setState(() {
        _activeDocument = widget.selectedDocument;
        if (widget.selectedDocument!.latitude != null &&
            widget.selectedDocument!.longitude != null) {
          _currentLat = widget.selectedDocument!.latitude!;
          _currentLng = widget.selectedDocument!.longitude!;
        }
        if (widget.selectedDocument!.physicalAddress != null) {
          _currentAddress = widget.selectedDocument!.physicalAddress!;
        }
      });
    }
  }

  Future<void> _openExternalMap(double lat, double lng, [String? label]) async {
    final query = Uri.encodeComponent(
      label != null && label.isNotEmpty ? '$lat,$lng ($label)' : '$lat,$lng',
    );
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    final osmUrl = Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(osmUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở ứng dụng bản đồ bên ngoài.')),
        );
      }
    }
  }

  void _selectPreset(TluPresetLocation preset) {
    setState(() {
      _currentLat = preset.latitude;
      _currentLng = preset.longitude;
      _currentAddress = preset.address;
    });
    widget.onLocationChanged?.call(preset.latitude, preset.longitude, preset.address);
  }

  @override
  Widget build(BuildContext context) {
    final documentsWithLocation = widget.documents
        .where((d) => d.latitude != null && d.longitude != null)
        .toList();

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF80CBC4), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15004D40),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header bản đồ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF00796B),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isPicker
                        ? 'Chọn vị trí lưu trữ vật lý'
                        : 'Bản đồ vị trí tài liệu (${documentsWithLocation.length} điểm)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Mở Google Maps',
                  icon: const Icon(Icons.open_in_new, color: Colors.white, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openExternalMap(
                    _currentLat,
                    _currentLng,
                    _activeDocument?.title ?? _currentAddress,
                  ),
                ),
              ],
            ),
          ),

          // Preset locations bar nếu ở chế độ picker
          if (widget.isPicker)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Địa điểm TLU: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ...tluPresetLocations.map((preset) {
                      final isSelected = (_currentLat - preset.latitude).abs() < 0.0001 &&
                          (_currentLng - preset.longitude).abs() < 0.0001;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(preset.name, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          selectedColor: const Color(0xFFB2DFDB),
                          onSelected: (_) => _selectPreset(preset),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

          // Vùng hiển thị bản đồ trực quan
          Expanded(
            child: Stack(
              children: [
                // Bản đồ nền vector phong cách học tập/khuôn viên
                _buildMapCanvas(documentsWithLocation),

                // Nút điều khiển Zoom
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom_in_${widget.key}',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF00796B),
                        onPressed: () {
                          setState(() {
                            _zoomLevel = math.min(_zoomLevel + 0.5, 19.0);
                          });
                        },
                        child: const Icon(Icons.add, size: 20),
                      ),
                      const SizedBox(height: 6),
                      FloatingActionButton.small(
                        heroTag: 'zoom_out_${widget.key}',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF00796B),
                        onPressed: () {
                          setState(() {
                            _zoomLevel = math.max(_zoomLevel - 0.5, 12.0);
                          });
                        },
                        child: const Icon(Icons.remove, size: 20),
                      ),
                    ],
                  ),
                ),

                // Card thông tin địa chỉ dưới cùng
                Positioned(
                  left: 12,
                  right: 60,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xF2FFFFFF),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_activeDocument != null) ...[
                          Text(
                            _activeDocument!.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D40),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          _activeDocument?.physicalAddress ?? _currentAddress,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[800],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tọa độ: ${_currentLat.toStringAsFixed(4)}, ${_currentLng.toStringAsFixed(4)} (Zoom: ${_zoomLevel.toStringAsFixed(1)}x)',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCanvas(List<Document> documentsWithLocation) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final center = Offset(width / 2, height / 2);

        return GestureDetector(
          onTapUp: widget.isPicker
              ? (details) {
                  // Tính toán độ lệch từ tâm theo zoom level
                  final dx = (details.localPosition.dx - center.dx) / (_zoomLevel * 120);
                  final dy = (details.localPosition.dy - center.dy) / (_zoomLevel * 120);
                  final newLng = _currentLng + dx;
                  final newLat = _currentLat - dy;
                  final newAddress = 'Vị trí đã chọn (${newLat.toStringAsFixed(4)}, ${newLng.toStringAsFixed(4)})';

                  setState(() {
                    _currentLat = newLat;
                    _currentLng = newLng;
                    _currentAddress = newAddress;
                  });
                  widget.onLocationChanged?.call(newLat, newLng, newAddress);
                }
              : null,
          child: CustomPaint(
            size: Size(width, height),
            painter: _MapGridPainter(
              zoomLevel: _zoomLevel,
              centerLat: _currentLat,
              centerLng: _currentLng,
            ),
            child: Stack(
              children: [
                // Render marker ở tâm cho vị trí hiện tại hoặc picker
                if (widget.isPicker || documentsWithLocation.isEmpty)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00796B),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: Text(
                            widget.isPicker ? 'Chạm để dời ghim' : 'Điểm lưu trữ',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.location_pin,
                          color: Colors.redAccent,
                          size: 38,
                        ),
                      ],
                    ),
                  ),

                // Render marker cho các tài liệu khác
                ...documentsWithLocation.map((doc) {
                  final dLng = doc.longitude! - _currentLng;
                  final dLat = doc.latitude! - _currentLat;
                  final x = center.dx + (dLng * _zoomLevel * 12000);
                  final y = center.dy - (dLat * _zoomLevel * 12000);

                  // Chỉ vẽ nếu nằm trong khung nhìn
                  if (x < -20 || x > width + 20 || y < -20 || y > height + 20) {
                    return const SizedBox.shrink();
                  }

                  final isSelected = _activeDocument?.id == doc.id;

                  return Positioned(
                    left: x - 18,
                    top: y - 36,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeDocument = doc;
                          _currentLat = doc.latitude!;
                          _currentLng = doc.longitude!;
                          if (doc.physicalAddress != null) {
                            _currentAddress = doc.physicalAddress!;
                          }
                        });
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.deepOrange : const Color(0xFF004D40),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 3),
                              ],
                            ),
                            child: Text(
                              doc.title,
                              style: const TextStyle(color: Colors.white, fontSize: 9),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.location_on,
                            color: isSelected ? Colors.deepOrange : const Color(0xFF00897B),
                            size: isSelected ? 34 : 26,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapGridPainter extends CustomPainter {
  _MapGridPainter({
    required this.zoomLevel,
    required this.centerLat,
    required this.centerLng,
  });

  final double zoomLevel;
  final double centerLat;
  final double centerLng;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF1F8E9);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Vẽ các khối khuôn viên mô phỏng
    final zonePaint = Paint()
      ..color = const Color(0xFFC8E6C9)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.15, size.height * 0.2, size.width * 0.3, size.height * 0.25),
        const Radius.circular(8),
      ),
      zonePaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.55, size.height * 0.35, size.width * 0.35, size.height * 0.3),
        const Radius.circular(8),
      ),
      zonePaint,
    );

    // Vẽ các trục đường
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke;

    final roadBorder = Paint()
      ..color = const Color(0xFFCFD8DC)
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.lineTo(size.width, size.height * 0.5);
    path.moveTo(size.width * 0.5, 0);
    path.lineTo(size.width * 0.5, size.height);

    canvas.drawPath(path, roadBorder);
    canvas.drawPath(path, roadPaint);

    // Tên khuôn viên
    const textStyle = TextStyle(
      color: Color(0xFF558B2F),
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
    );
    const textSpan = TextSpan(text: 'ĐẠI HỌC THỦY LỢI (TLU)', style: textStyle);
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.18, size.height * 0.25));
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) {
    return oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.centerLat != centerLat ||
        oldDelegate.centerLng != centerLng;
  }
}
