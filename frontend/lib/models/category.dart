/// Beauty category (backend `categories.Category`).
class Category {
  const Category({
    required this.id,
    required this.slug,
    required this.name,
    this.description = '',
    this.iconMediaId,
    this.imageUrl = '',
    this.displayOrder = 0,
    this.isActive = true,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      iconMediaId: json['icon_media_id'] as String?,
      imageUrl: json['image_url'] as String? ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String slug;
  final String name;
  final String description;
  final String? iconMediaId;
  final String imageUrl;
  final int displayOrder;
  final bool isActive;

  bool get hasImage => imageUrl.isNotEmpty;
}
