import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Google Play Billing integration for the ArthaNote Pro subscription.
///
/// Product setup required in Play Console (Monetise with Play → Products):
///   - Subscription product id `arthanote_pro`, with two base plans:
///       id `monthly` → ₹199 / month
///       id `yearly`  → ₹999 / year
///   - One-time (non-consumable) product id `arthanote_lifetime` → ₹1999
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

  static const subscriptionProductId = 'arthanote_pro';
  static const lifetimeProductId = 'arthanote_lifetime';
  static const monthlyBasePlanId = 'monthly';
  static const yearlyBasePlanId = 'yearly';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = [];
  bool _initialized = false;

  /// Best-effort hint for which base plan a subscription purchase was
  /// launched for — Play's purchase callback doesn't reliably expose which
  /// base plan (monthly/yearly) of one subscription product was bought
  /// without server-side verification, so we remember what the UI asked
  /// for. Falls back to 'monthly' if the app was killed mid-flow and this
  /// in-memory hint was lost (e.g. purchase resolved via restorePurchases
  /// on next launch).
  String? _pendingPlanId;

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
      final resp = await _iap
          .queryProductDetails({subscriptionProductId, lifetimeProductId});
      _products = resp.productDetails;
    } catch (_) {}
  }

  void dispose() => _sub?.cancel();

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Launches the Play Billing purchase sheet for [planId]
  /// ('monthly' | 'yearly' | 'lifetime'). Fire-and-forget — the actual Pro
  /// grant happens asynchronously via the purchase stream once Play
  /// confirms the purchase.
  Future<void> buy(String planId) async {
    if (!await _iap.isAvailable()) {
      throw Exception('Google Play Billing is not available on this device');
    }
    if (_products.isEmpty) {
      final resp = await _iap
          .queryProductDetails({subscriptionProductId, lifetimeProductId});
      _products = resp.productDetails;
    }

    if (planId == 'lifetime') {
      final product = _products.where((p) => p.id == lifetimeProductId);
      if (product.isEmpty) {
        throw Exception('Lifetime plan is not available right now');
      }
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product.first));
      return;
    }

    final product = _products.where((p) => p.id == subscriptionProductId);
    if (product.isEmpty) {
      throw Exception('Subscription plan is not available right now');
    }
    final basePlanId = planId == 'yearly' ? yearlyBasePlanId : monthlyBasePlanId;
    _pendingPlanId = planId;

    final details = product.first;
    if (details is GooglePlayProductDetails) {
      final offerList = details.subscriptionOfferDetails ?? const [];
      final offers =
          offerList.where((o) => o.basePlanId == basePlanId).toList();
      if (offers.isEmpty) {
        throw Exception('$planId plan is not available right now');
      }
      final param = GooglePlayPurchaseParam(
          productDetails: details, offerToken: offers.first.offerToken);
      await _iap.buyNonConsumable(purchaseParam: param);
    } else {
      // Fallback for non-Android platforms / older plugin versions without
      // base-plan support — buys the product's default offer.
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: details));
    }
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

    String planType;
    DateTime? expiry;
    if (p.productID == lifetimeProductId) {
      planType = 'lifetime';
      expiry = null;
    } else {
      planType = _pendingPlanId ?? 'monthly';
      expiry = DateTime.now().add(Duration(days: planType == 'yearly' ? 365 : 30));
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
