import 'dart:convert';
import 'package:http/http.dart' as http;

class NaverPlaceService {
  NaverPlaceService._();

  static const String _clientId = String.fromEnvironment(
    'NAVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String _clientSecret = String.fromEnvironment(
    'NAVER_CLIENT_SECRET',
    defaultValue: '',
  );

  static const String _baseUrl =
      'https://openapi.naver.com/v1/search/local.json';

  static Future<List<PlaceResult>> searchBowlingAlley(String query) async {
    if (_clientId.isEmpty || query.trim().isEmpty) return [];

    final searchQuery = query.contains('볼링') ? query : '$query 볼링장';

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'query': searchQuery,
      'display': '5',
      'sort': 'random',
    });

    try {
      final response = await http.get(
        uri,
        headers: {
          'X-Naver-Client-Id': _clientId,
          'X-Naver-Client-Secret': _clientSecret,
        },
      );

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>;

      return items
          .map((item) => PlaceResult.fromNaverJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

class PlaceResult {
  final String placeName;
  final String addressName;
  final String? roadAddressName;
  final String? phone;

  const PlaceResult({
    required this.placeName,
    required this.addressName,
    this.roadAddressName,
    this.phone,
  });

  factory PlaceResult.fromNaverJson(Map<String, dynamic> json) {
    // 네이버 API는 HTML 태그(<b>)를 포함하므로 제거
    String clean(String? s) => (s ?? '').replaceAll(RegExp(r'<[^>]*>'), '');

    return PlaceResult(
      placeName: clean(json['title'] as String?),
      addressName: json['address'] as String? ?? '',
      roadAddressName: json['roadAddress'] as String?,
      phone: json['telephone'] as String?,
    );
  }
}
