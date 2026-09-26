import 'feature_registry.dart';

class AccountingRoute {
  const AccountingRoute(this.feature);

  final AccountingFeature feature;
}

class AccountingRouting {
  AccountingRouting._();

  static AccountingRoute? resolve(String path) {
    final feature = FeatureRegistry.byPath(path);
    return feature == null ? null : AccountingRoute(feature);
  }

  static AccountingRoute? forFeature(String featureId) {
    final feature = FeatureRegistry.byId(featureId);
    return feature == null ? null : AccountingRoute(feature);
  }
}
