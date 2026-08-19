import 'category.dart';
import 'professional.dart';

/// Category detail plus its professionals (`GET /discovery/categories/{slug}`).
class CategoryResult {
  const CategoryResult({required this.category, required this.professionals});

  factory CategoryResult.fromJson(Map<String, dynamic> json) {
    return CategoryResult(
      category: Category.fromJson(json['category'] as Map<String, dynamic>? ?? const {}),
      professionals: [
        for (final item in json['professionals'] as List? ?? const [])
          if (item is Map<String, dynamic>) Professional.fromJson(item),
      ],
    );
  }

  final Category category;
  final List<Professional> professionals;
}
