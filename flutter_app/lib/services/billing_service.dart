import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Google Play Billing integration for the ArthaNote Pro subscription.
///
/// Product setup required in Play Console (Monetise with Play → Products):
///   - Subscription product id `arthanote_pro_monthly` → ₹199 / month
///   - Subscription product id `arthanote_pro_yearly`  → ₹999 / year
///   - One-time (non-consumable) product id `arthanote_lifetime` → ₹1999
///
/// Deliberately THREE separate flat products rather than one subscription
/// with multiple "base plans" — the base-plan/offer-selection API
/// (GooglePlayPurchaseParam.offerToken) only landed in
/// in_app_purchase_android 0.4.0+2, which requires Flutter >=3.27 / Dart
/// SDK ^3.6.0, newer than this project's pinned Flutter (3.24.5). Three
/// flat products work with the older, already-verified plugin version and
/// need no offer-token/base-plan lookup at all — simpler and more robust.
///
/// NOTE ON SECURITY — same client-trust model as promo_service.dart: there is
/// no backend yet to verify a purchase token server-side via the Play
/// Developer API, so Pro is granted client-side on receiving a
/// 'purchased'/'restored' event. Hardening this (a Cloud Function verifying
/// receipts, ideally driven by Real-Time Developer Notifications) is a later
/// phase, same as documented for promo codes. This is a business-logic gate,
/// not a hard security boundary — Firestore rules already let a user write
/// pro:true on their own staff doc (same as the trial mechanism).
class BillingService {
  BillingService._();
  static final BillingService _instance = BillingService._();
  factory BillingService() => _instance;

  static const monthlyProductId = 'arthanote_pro_monthly';
  static const yearlyProductId = 'arthanote_pro_yearly';
  static const lifetimeProductId = 'arthanote_lifetime';
  static const _allProductIds = {
    monthlyProductId,
    yearlyProductId,
    lifetimeProductId,
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = [];
  bool _initialized = false;

  /// Called after Pro is successfully granted from a purchase, so the app
  /// can refresh its in-memory profile (the purchase stream can fire at any
  /// time, independent of which screen is on-screen).
  void Function()? onGranted;

  Future<void> init({void Function()? onGranted}) async {
    this.onGranted = onGranted;
    if (_initialized) return;
    _initialized = true;
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});
    try {
      final resp = await _iap.queryProductDetails(_allProductIds);
      _products = resp.productDetails;
    } catch (_) {}
  }

  void dispose() => _sub?.cancel();

  Future<bool> isAvailable() => _iap.isAvailable();

  static String _productIdFor(String planId) => switch (planId) {
        'yearly' => yearlyProductId,
        'lifetime' => lifetimeProductId,
        _ => monthlyProductId,
      };

  /// Launches the Play Billing purchase sheet for [planId]
  /// ('monthly' | 'yearly' | 'lifetime'). Fire-and-forget — the actual Pro
  /// grant happens asynchronously via the purchase stream once Play
  /// confirms the purchase.
  Future<void> buy(String planId) async {
    if (!await _iap.isAvailable()) {
      throw Exception('Google Play Billing is not available on this device');
    }
    if (_products.isEmpty) {
      final resp = await _iap.queryProductDetails(_allProductIds);
      _products = resp.productDetails;
    }

    final productId = _productIdFor(planId);
    final match = _products.where((p) => p.id == productId);
    if (match.isEmpty) {
      throw Exception('This plan is not available right now');
    }
    await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: match.first));
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) continue;
      if (p.status == PurchaseStatus.error) {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        continue;
      }
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _grantEntitlement(p);
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> _grantEntitlement(PurchaseDetails p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // The product ID itself unambiguously identifies the plan — no
    // guessing needed (each plan is its own flat product).
    String planType;
    DateTime? expiry;
    switch (p.productID) {
      case lifetimeProductId:
        planType = 'lifetime';
        expiry = null;
      case yearlyProductId:
        planType = 'yearly';
        expiry = DateTime.now().add(const Duration(days: 365));
      default:
        planType = 'monthly';
        expiry = DateTime.now().add(const Duration(days: 30));
    }

    final entitlement = <String, dynamic>{
      'pro': true,
      'planType': planType,
      'proSource': 'play_billing:${p.productID}',
      'billingPurchaseId': p.purchaseID ?? '',
      'billingGrantedAt': FieldValue.serverTimestamp(),
      'proExpiry':
          expiry != null ? Timestamp.fromDate(expiry) : FieldValue.delete(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('staff')
          .doc(uid)
          .set(entitlement, SetOptions(merge: true));
      onGranted?.call();
    } catch (_) {
      // Non-fatal — the purchase is still valid on Play's side and will be
      // picked up again via restorePurchases() next launch.
    }
  }
}
