import 'beauty_service.dart';
import 'category.dart';
import 'deal.dart';
import 'professional.dart';

/// Curated payload for the Home feed (`GET /discovery/home`).
class HomeFeed {
  const HomeFeed({
    required this.categories,
    required this.professionals,
    required this.services,
    required this.deals,
  });

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    return HomeFeed(
      categories: _list(json['categories'], Category.fromJson),
      professionals: _list(json['professionals'], Professional.fromJson),
      services: _list(json['services'], BeautyService.fromJson),
      deals: _list(json['deals'], Deal.fromJson),
    );
  }

  final List<Category> categories;
  final List<Professional> professionals;
  final List<BeautyService> services;
  final List<Deal> deals;
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  final items = value as List? ?? const [];
  return [
    for (final item in items)
      if (item is Map<String, dynamic>) fromJson(item),
  ];
}
