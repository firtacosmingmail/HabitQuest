import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ad_service.dart';

/// Runs ad consent (UMP, then ATT on iOS) and starts the ads SDK once the
/// first frame is up, so the consent form has a screen to show on. Wraps
/// the app in `main.dart`; no ad is requested before this finishes.
class AdsBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const AdsBootstrap({super.key, required this.child});

  @override
  ConsumerState<AdsBootstrap> createState() => _AdsBootstrapState();
}

class _AdsBootstrapState extends ConsumerState<AdsBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(adServiceProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
