import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdService — manages all AdMob ad units.
/// Uses TEST IDs by default. Replace with real IDs before Play Store release.
/// 
/// TEST IDs (safe to use during development):
///   App ID:        ca-app-pub-3940256099942544~3347511713  (in AndroidManifest)
///   Banner:        ca-app-pub-3940256099942544/6300978111
///   Interstitial:  ca-app-pub-3940256099942544/1033173712
///
/// REAL IDs: Replace the strings below once you create ad units in AdMob console.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  // ── Ad Unit IDs ──────────────────────────────────────────────────────────
  static const String _dashboardBannerAdId = 'ca-app-pub-2230166638083802/1588934904';
  static const String _aiHubBannerAdId     = 'ca-app-pub-2230166638083802/2710444885';
  InterstitialAd? _interstitialAd;

  // ── Initialize ────────────────────────────────────────────────────────────
  Future<void> init() async {
    await MobileAds.instance.initialize();
  }

  // ── Banners ───────────────────────────────────────────────────────────────
  BannerAd createDashboardBannerAd({required BannerAdListener listener}) {
    return BannerAd(
      adUnitId: _dashboardBannerAdId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: listener,
    )..load();
  }

  BannerAd createAiHubBannerAd({required BannerAdListener listener}) {
    return BannerAd(
      adUnitId: _aiHubBannerAdId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: listener,
    )..load();
  }
}
