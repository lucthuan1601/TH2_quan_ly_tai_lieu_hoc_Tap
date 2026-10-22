enum DocumentType {
  lecture('Bài giảng'),
  assignment('Bài tập'),
  reference('Tài liệu tham khảo');

  const DocumentType(this.label);
  final String label;
}

extension DocumentTypeCodec on DocumentType {
  static DocumentType fromValue(String value) => DocumentType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => DocumentType.reference,
      );
}

class DocumentLocation {
  const DocumentLocation({
    this.address,
    this.latitude,
    this.longitude,
  });

  final String? address;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasLocation => (address != null && address!.trim().isNotEmpty) || hasCoordinates;

  String get displayAddress =>
      (address != null && address!.trim().isNotEmpty) ? address!.trim() : 'Chưa có địa chỉ cụ thể';

  String get coordinatesDisplay =>
      hasCoordinates ? '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}' : '';
}

/// Danh sách các địa điểm mẫu tại Trường Đại học Thủy Lợi (TLU)
class TluPresetLocation {
  const TluPresetLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
}

const List<TluPresetLocation> tluPresetLocations = [
  TluPresetLocation(
    name: 'Thư viện TLU (Tòa A2)',
    address: 'Thư viện tầng 3 - Tòa nhà A2, ĐH Thủy Lợi, 175 Tây Sơn, Đống Đa, Hà Nội',
    latitude: 21.0074,
    longitude: 105.8248,
  ),
  TluPresetLocation(
    name: 'Khoa CNTT (Tòa C1)',
    address: 'Văn phòng Khoa CNTT, Tòa C1, ĐH Thủy Lợi, 175 Tây Sơn, Hà Nội',
    latitude: 21.0071,
    longitude: 105.8242,
  ),
  TluPresetLocation(
    name: 'Giảng đường B1',
    address: 'Giảng đường B1, ĐH Thủy Lợi, 175 Tây Sơn, Đống Đa, Hà Nội',
    latitude: 21.0068,
    longitude: 105.8249,
  ),
  TluPresetLocation(
    name: 'Phòng học P301 (Tòa A1)',
    address: 'Phòng 301, Tòa nhà A1, ĐH Thủy Lợi, Hà Nội',
    latitude: 21.0076,
    longitude: 105.8252,
  ),
  TluPresetLocation(
    name: 'Ký túc xá TLU',
    address: 'Khu KTX sinh viên, ĐH Thủy Lợi, 175 Tây Sơn, Hà Nội',
    latitude: 21.0080,
    longitude: 105.8235,
  ),
];

const List<String> defaultSuggestedTags = [
  'Toán',
  'Giải tích',
  'CNTT',
  'Lập trình Flutter',
  'Cơ sở dữ liệu',
  'Mạng máy tính',
  'Đại cương',
  'Bài tập lớn',
  'Đồ án',
  'Tài liệu tham khảo',
  'Giáo trình',
];

/// Tiện ích chuẩn hoá và tách/ghép tags
List<String> parseTags(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();
}

String formatTags(List<String> tags) {
  return tags
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet()
      .join(', ');
}
