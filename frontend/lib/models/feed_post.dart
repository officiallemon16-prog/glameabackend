/// One image in a feed post carousel (backend `posts.PostImage`).
class PostImage {
  const PostImage({required this.url});

  factory PostImage.fromJson(Map<String, dynamic> json) {
    return PostImage(url: json['url'] as String? ?? '');
  }

  final String url;
}

/// Author profile attached to a feed post (backend `posts.PostAuthor`).
class PostAuthor {
  const PostAuthor({
    this.id = '',
    this.name = '',
    this.avatarUrl = '',
    this.city = '',
    this.rating = 0,
    this.reviewCount = 0,
    this.verified = false,
    this.latitude,
    this.longitude,
  });

  factory PostAuthor.fromJson(Map<String, dynamic> json) {
    return PostAuthor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      city: json['city'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      verified: json['verified'] as bool? ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String name;
  final String avatarUrl;
  final String city;
  final double rating;
  final int reviewCount;
  final bool verified;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;
}

/// Instagram-style feed post (backend `posts.FeedPost`).
class FeedPost {
  const FeedPost({
    required this.id,
    required this.professionalId,
    this.categoryId,
    this.caption = '',
    this.location = '',
    this.sponsored = false,
    this.createdAt,
    this.categorySlug = '',
    this.categoryName = '',
    this.images = const [],
    required this.professional,
    this.likeCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    final authorJson = json['professional'];
    return FeedPost(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      caption: json['caption'] as String? ?? '',
      location: json['location'] as String? ?? '',
      sponsored: json['sponsored'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      categorySlug: json['category_slug'] as String? ?? '',
      categoryName: json['category_name'] as String? ?? '',
      images: _imageList(json['images']),
      professional: authorJson is Map<String, dynamic>
          ? PostAuthor.fromJson(authorJson)
          : const PostAuthor(),
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      likedByMe: json['liked_by_me'] as bool? ?? false,
      savedByMe: json['saved_by_me'] as bool? ?? false,
    );
  }

  final String id;
  final String professionalId;
  final String? categoryId;
  final String caption;
  final String location;
  final bool sponsored;
  final DateTime? createdAt;
  final String categorySlug;
  final String categoryName;
  final List<PostImage> images;
  final PostAuthor professional;
  final int likeCount;
  final bool likedByMe;
  final bool savedByMe;

  String get coverUrl => images.isNotEmpty ? images.first.url : '';

  FeedPost copyWith({int? likeCount, bool? likedByMe, bool? savedByMe}) {
    return FeedPost(
      id: id,
      professionalId: professionalId,
      categoryId: categoryId,
      caption: caption,
      location: location,
      sponsored: sponsored,
      createdAt: createdAt,
      categorySlug: categorySlug,
      categoryName: categoryName,
      images: images,
      professional: professional,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      savedByMe: savedByMe ?? this.savedByMe,
    );
  }
}

List<PostImage> _imageList(dynamic value) {
  final items = value as List? ?? const [];
  return [
    for (final item in items)
      if (item is Map<String, dynamic>) PostImage.fromJson(item),
  ];
}

/// Paged feed response (`GET /feed`).
class FeedResult {
  const FeedResult({this.posts = const [], this.total = 0});

  factory FeedResult.fromJson(Map<String, dynamic> json) {
    return FeedResult(
      posts: _postList(json['posts']),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  final List<FeedPost> posts;
  final int total;
}

List<FeedPost> _postList(dynamic value) {
  final items = value as List? ?? const [];
  return [
    for (final item in items)
      if (item is Map<String, dynamic>) FeedPost.fromJson(item),
  ];
}
