import 'beauty_service.dart';
import 'professional.dart';

/// Search results (`GET /discovery/search`).
class SearchResult {
  const SearchResult({required this.professionals, required this.services, this.total = 0});

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      professionals: _list(json['professionals'], Professional.fromJson),
      services: _list(json['services'], BeautyService.fromJson),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  final List<Professional> professionals;
  final List<BeautyService> services;
  final int total;
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  final items = value as List? ?? const [];
  return [
    for (final item in items)
      if (item is Map<String, dynamic>) fromJson(item),
  ];
}
