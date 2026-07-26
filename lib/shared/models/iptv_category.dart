class IptvCategory {
  const IptvCategory({
    required this.id,
    required this.name,
    this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;

  factory IptvCategory.fromJson(Map<String, dynamic> json) {
    return IptvCategory(
      id: json['category_id']?.toString() ?? '',
      name: json['category_name']?.toString().trim() ?? 'Sin nombre',
      parentId: json['parent_id']?.toString(),
    );
  }
}