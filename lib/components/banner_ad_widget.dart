import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Test banner ad unit ID — safe for dev / CI. Swap to [prodBannerAdUnitId]
/// in a release build once the real ID has been approved by AdMob.
const String testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

/// Self-contained banner ad. Shows nothing if the ad fails to load so it
/// never breaks layout. Dispose is handled internally — callers don't need
/// to manage the [BannerAd] lifecycle.
class BannerAdWidget extends StatefulWidget {
  final String adUnitId;

  const BannerAdWidget({
    super.key,
    this.adUnitId = testBannerAdUnitId,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      final ad = BannerAd(
        adUnitId: widget.adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (!mounted) return;
            setState(() => _loaded = true);
          },
        ),
      );
      await ad.load();
      if (!mounted) {
        ad.dispose();
        return;
      }
      _ad = ad;
    } catch (_) {
      // AdMob plugin not available on this platform / CI — silently skip.
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
