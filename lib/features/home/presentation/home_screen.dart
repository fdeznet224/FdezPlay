import 'package:flutter/material.dart';

import '../../auth/domain/auth_session.dart';
import '../../device_mode/domain/device_mode.dart';
import 'mobile/mobile_home_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.mode,
    required this.session,
    super.key,
  });

  final DeviceMode mode;
  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case DeviceMode.mobile:
        return MobileHomeScreen(session: session);
      case DeviceMode.tablet:
        return MobileHomeScreen(
          session: session,
          useSideNavigation: true,
        );
      case DeviceMode.television:
        return MobileHomeScreen(
          session: session,
          useSideNavigation: true,
          enableTvRemoteNavigation: true,
        );
    }
  }
}
