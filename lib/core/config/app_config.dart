class AppConfig {
  AppConfig._();

  static const List<String> servers = [
    'http://legazy.icu:8880',
    'http://azyleg.xyz:8880',
  ];

  static const Duration connectionTimeout = Duration(seconds: 10);
}
