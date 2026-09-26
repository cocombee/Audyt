import 'dart:io' show Platform;

class PlatformCapabilities {
  const PlatformCapabilities({required this.isDesktop, required this.isMobile});

  final bool isDesktop;
  final bool isMobile;

  factory PlatformCapabilities.detect() {
    final desktop = Platform.isMacOS || Platform.isWindows;
    final mobile = Platform.isIOS || Platform.isAndroid;
    return PlatformCapabilities(isDesktop: desktop, isMobile: mobile);
  }
}
