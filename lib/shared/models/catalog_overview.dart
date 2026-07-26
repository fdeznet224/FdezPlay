import 'iptv_category.dart';

class CatalogOverview {
  const CatalogOverview({
    required this.liveCategories,
    required this.movieCategories,
    required this.seriesCategories,
  });

  final List<IptvCategory> liveCategories;
  final List<IptvCategory> movieCategories;
  final List<IptvCategory> seriesCategories;

  int get liveCategoryCount => liveCategories.length;
  int get movieCategoryCount => movieCategories.length;
  int get seriesCategoryCount => seriesCategories.length;
}