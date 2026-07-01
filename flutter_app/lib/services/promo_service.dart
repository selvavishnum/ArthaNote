import 'package:cloud_firestore/cloud_firestore.dart';

/// Outcome of a promo-code redemption attempt.
class PromoResult {
  final bool ok;
  final String message;
  final String? planType; // 'monthly' | 'yearly' | 'lifetime' | 'pro'
  final DateTime? proExpiry; // null = lifetime / no expiry
  const PromoResult(this.ok, this.message, {this.planType, this.proExpiry});
}

/// Validates and redeems promo codes stored in the `promo_codes` collection.
///
/// A promo code document (doc id == the UPPERCASE code) looks like:
/// ```
/// promo_codes/FOUNDER100 {
///   planType:      'yearly',      // what plan the code grants
///   durationDays:  365,           // ignored when planType == 'lifetime'
///   maxUses:       1000,          // <= 0 means unlimited
///   usedCount:     42,            // incremented on each redemption
///   usedBy:        ['uid1', ...], // prevents double-redemption
///   expiresAt:     <Timestamp>,   // the CODE's own expiry (null = never)
///   active:        true,
///   note:          'Founding members',
/// }
/// ```
///
/// NOTE ON SECURITY: this app is client-trusted — the Firestore rules already
/// let a user write `pro:true` onto their own `staff/{uid}` doc (same as the
/// trial mechanism). So promo validation here is a business-logic gate, not a
/// hard security boundary; hardening (a Cloud Function that mints entitlements)
/// is the same later phase as Play-billing receipt verification. The rules do
/// restrict the redemption write on `promo_codes` to only `usedCount`/`usedBy`.
class PromoService {
  final _db = FirebaseFirestore.instance;

  Future<PromoResult> redeem(String rawCode, String uid) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) return const PromoResult(false, 'Enter a code');
    if (uid.isEmpty) return const PromoResult(false, 'Please log in first');

    final ref = _db.collection('promo_codes').doc(code);
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get();
    } catch (_) {
      return const PromoResult(false, 'Network error — try again');
    }
    if (!snap.exists) return const PromoResult(false, 'Invalid code');
    final d = snap.data() ?? const {};

    if (d['active'] == false) {
      return const PromoResult(false, 'This code is no longer active');
    }

    final expiresAt = d['expiresAt'];
    if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
      return const PromoResult(false, 'This code has expired');
    }

    final usedBy = (d['usedBy'] as List?)?.whereType<String>().toList() ?? const [];
    if (usedBy.contains(uid)) {
      return const PromoResult(false, 'You have already used this code');
    }

    final maxUses = (d['maxUses'] as num?)?.toInt() ?? 1;
    final usedCount = (d['usedCount'] as num?)?.toInt() ?? usedBy.length;
    if (maxUses > 0 && usedCount >= maxUses) {
      return const PromoResult(false, 'This code has reached its usage limit');
    }

    final ptRaw = (d['planType'] as String?)?.trim();
    final planType = (ptRaw != null && ptRaw.isNotEmpty) ? ptRaw : 'pro';
    final durationDays = (d['durationDays'] as num?)?.toInt() ?? 0;
    final lifetime = planType == 'lifetime' || durationDays <= 0;
    final proExpiry =
        lifetime ? null : DateTime.now().add(Duration(days: durationDays));

    // 1) Record the redemption first. Fail closed: if we can't mark it used
    //    (e.g. it just hit its limit in a race), don't grant Pro.
    try {
      await ref.update({
        'usedCount': FieldValue.increment(1),
        'usedBy': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {
      return const PromoResult(false, 'Could not redeem right now — try again');
    }

    // 2) Grant Pro on the user's own staff doc.
    final entitlement = <String, dynamic>{
      'pro': true,
      'planType': planType,
      'proSource': 'promo:$code',
      'promoRedeemedAt': FieldValue.serverTimestamp(),
      'proExpiry':
          proExpiry != null ? Timestamp.fromDate(proExpiry) : FieldValue.delete(),
    };
    try {
      await _db.collection('staff').doc(uid).set(entitlement, SetOptions(merge: true));
    } catch (_) {
      // Roll back the usage record so the code isn't burned for nothing.
      try {
        await ref.update({
          'usedCount': FieldValue.increment(-1),
          'usedBy': FieldValue.arrayRemove([uid]),
        });
      } catch (_) {}
      return const PromoResult(false, 'Could not activate Pro — try again');
    }

    final label = lifetime
        ? 'Lifetime Pro unlocked! 🎉'
        : 'Pro unlocked until ${_fmt(proExpiry!)} 🎉';
    return PromoResult(true, label, planType: planType, proExpiry: proExpiry);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
