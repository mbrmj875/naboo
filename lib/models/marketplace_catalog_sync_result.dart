class MarketplaceCatalogSyncResult {
  const MarketplaceCatalogSyncResult({
    required this.published,
    required this.unpublished,
    required this.skipped,
    this.storeName,
  });

  final int published;
  final int unpublished;
  final int skipped;
  final String? storeName;

  int get total => published + unpublished + skipped;
}
