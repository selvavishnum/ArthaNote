import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<UserCredential> signInEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<UserCredential> registerEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<UserCredential?> signInGoogle() async {
    final googleSignIn = GoogleSignIn();
    final account = await googleSignIn.signIn();
    if (account == null) return null;
    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken:     googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // GoogleSignIn may not be initialized if user didn't use Google
    }
    await _auth.signOut();
  }

  // ── Profile (staff collection) ───────────────────────────────────────────

  Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('staff').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> saveProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('staff').doc(uid).set(data, SetOptions(merge: true));

  // ── Config (config collection) ───────────────────────────────────────────

  Future<Map<String, dynamic>?> getConfig(String businessId) async {
    final doc = await _db.collection('config').doc(businessId).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> saveConfig(String businessId, Map<String, dynamic> data) =>
      _db.collection('config').doc(businessId).set(data, SetOptions(merge: true));

  /// Replaces the 'shops' field entirely — use when deleting shops so
  /// removed keys are actually gone (set+merge only updates, never removes).
  Future<void> saveShops(String businessId, Map<String, dynamic> shops) async {
    try {
      await _db.collection('config').doc(businessId).update({'shops': shops});
    } catch (_) {
      // Doc may not exist yet for a brand-new account — fall back to set
      await _db.collection('config').doc(businessId).set({'shops': shops}, SetOptions(merge: true));
    }
  }

  // ── Staff App Access ──────────────────────────────────────────────────────

  Future<void> grantStaffAccess({
    required String businessId,
    required String email,
    required String shopId,
    required String shopName,
    required String role,
  }) async {
    final snap = await _db
        .collection('staff')
        .where('email', isEqualTo: email)
        .where('businessId', isEqualTo: businessId)
        .limit(3)
        .get();
    // Only ever touch a grant doc here, never a staff member's own self
    // profile doc (which also carries a 'uid' field) — those two shapes can
    // both match this email+businessId query.
    QueryDocumentSnapshot<Map<String, dynamic>>? grantDoc;
    for (final d in snap.docs) {
      if (!d.data().containsKey('uid')) { grantDoc = d; break; }
    }
    if (grantDoc != null) {
      await _db.collection('staff').doc(grantDoc.id).update({
        'shop': shopId, 'role': role, 'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('staff').add({
        'email': email,
        'businessId': businessId,
        'shop': shopId,
        'shopName': shopName,
        'role': role,
        'accessGrantedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> revokeStaffAccess(String docId) async {
    await _db.collection('staff').doc(docId).delete();
  }

  /// Permanently deletes the account and ALL data for this businessId.
  /// Deletes: transactions, supplier_bills, suppliers, staff docs, config doc,
  /// and finally the Firebase Auth account. Uses batched writes (400 per batch)
  /// to handle large datasets without hitting Firestore limits.
  Future<void> deleteAccount(String businessId) async {
    Future<void> _deleteQuery(Query<Map<String, dynamic>> q) async {
      while (true) {
        final snap = await q.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    // Delete all business data in parallel
    await Future.wait([
      _deleteQuery(_db.collection('transactions')
          .where('businessId', isEqualTo: businessId)),
      _deleteQuery(_db.collection('supplier_bills')
          .where('businessId', isEqualTo: businessId)),
      _deleteQuery(_db.collection('suppliers')
          .where('businessId', isEqualTo: businessId)),
      _deleteQuery(_db.collection('staff')
          .where('businessId', isEqualTo: businessId)),
    ]);

    // Delete config doc
    await _db.collection('config').doc(businessId).delete();

    // Delete Firebase Auth account last
    await _auth.currentUser?.delete();
  }

  Stream<List<Map<String, dynamic>>> staffAccessStream(String businessId) {
    return _db
        .collection('staff')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((s) => s.docs
            .where((d) {
              final data  = d.data();
              final email = (data['email'] as String?)?.trim() ?? '';
              final role  = (data['role']  as String?)?.toLowerCase() ?? '';
              // Show only granted staff — exclude the owner's own profile doc
              return email.isNotEmpty && role != 'owner';
            })
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }
}
