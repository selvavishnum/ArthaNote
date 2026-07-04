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
    String name = '',
  }) async {
    // Canonical form — the login-time email auto-link looks grants up by the
    // signed-in account's (lowercased) email.
    email = email.trim().toLowerCase();
    name  = name.trim();
    final snap = await _db
        .collection('staff')
        .where('email', isEqualTo: email)
        .where('businessId', isEqualTo: businessId)
        .limit(5)
        .get();
    // The email+businessId query matches two doc shapes: the owner's GRANT
    // doc (no 'uid') and — once the staff has logged in — their own linked
    // self-profile (has 'uid'). Upsert the grant, and mirror shop/role/name
    // onto any linked profile so edits reach the staff on their next open.
    QueryDocumentSnapshot<Map<String, dynamic>>? grantDoc;
    for (final d in snap.docs) {
      if (!d.data().containsKey('uid')) { grantDoc = d; break; }
    }
    final fields = <String, dynamic>{
      'shop': shopId,
      'shopName': shopName,
      'role': role,
      if (name.isNotEmpty) 'name': name,
    };
    if (grantDoc != null) {
      await _db.collection('staff').doc(grantDoc.id).update({
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _db.collection('staff').add({
        'email': email,
        'businessId': businessId,
        ...fields,
        'accessGrantedAt': FieldValue.serverTimestamp(),
      });
    }
    // Propagate to the staff member's linked self-profile(s), if any.
    for (final d in snap.docs) {
      if (d.data().containsKey('uid')) {
        try {
          await _db.collection('staff').doc(d.id).update(fields);
        } catch (_) {}
      }
    }
  }

  Future<void> revokeStaffAccess(String docId) async {
    await _db.collection('staff').doc(docId).delete();
  }

  /// Finds an owner-created staff-access GRANT doc for this email (grant docs
  /// never carry a 'uid' field — that shape is a self profile). Tries the
  /// lowercased email first (new grants are stored lowercased), then the raw
  /// form for older grants typed with capitals.
  Future<Map<String, dynamic>?> findStaffGrantByEmail(String email) async {
    Future<Map<String, dynamic>?> lookup(String e) async {
      if (e.isEmpty || !e.contains('@')) return null;
      final snap = await _db
          .collection('staff')
          .where('email', isEqualTo: e)
          .limit(5)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        if (!data.containsKey('uid')) return data;
      }
      return null;
    }

    final trimmed = email.trim();
    return await lookup(trimmed.toLowerCase()) ??
        (trimmed != trimmed.toLowerCase() ? await lookup(trimmed) : null);
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

  // ── Account deletion security ──────────────────────────────────────────────

  /// True if the signed-in user authenticates with Google (vs email/password).
  /// Used to decide which re-verification UI to show before deletion.
  bool get isGoogleUser =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'google.com') ??
      false;

  /// Re-verifies the current user's identity immediately before a sensitive
  /// action (account deletion). This is the possession/knowledge factor that
  /// stops anyone who merely knows the (publicly visible) business name from
  /// deleting the account — they now also need the password or the Google
  /// account. It additionally clears Firebase's `requires-recent-login`
  /// restriction so the subsequent delete cannot fail.
  ///
  /// Throws a [FirebaseAuthException] on wrong password, cancellation, etc.
  Future<void> reauthenticate({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
          code: 'no-current-user', message: 'You are not signed in.');
    }

    if (isGoogleUser) {
      // Re-run Google sign-in to obtain a fresh credential, then re-auth.
      final account = await GoogleSignIn().signIn();
      if (account == null) {
        throw FirebaseAuthException(
            code: 'cancelled', message: 'Verification was cancelled.');
      }
      final googleAuth = await account.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(cred);
    } else {
      if (password == null || password.isEmpty) {
        throw FirebaseAuthException(
            code: 'missing-password',
            message: 'Please enter your password to continue.');
      }
      final email = user.email;
      if (email == null) {
        throw FirebaseAuthException(
            code: 'no-email', message: 'No email is linked to this account.');
      }
      final cred =
          EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(cred);
    }
  }

  /// Soft-deletes the account: flags it for permanent deletion after a 30-day
  /// grace period, then signs the user out. The underlying data is RETAINED
  /// during the grace window, so an accidental or malicious deletion can still
  /// be reversed by logging back in (see [cancelAccountDeletion]) — this is the
  /// safety net against the irreversible "type the name and it's gone" problem.
  ///
  /// Call [reauthenticate] first. The actual data purge after the grace period
  /// is performed by [deleteAccount] (run lazily on next sign-in past the
  /// scheduled date, by the admin panel, or by a scheduled Cloud Function).
  Future<void> requestAccountDeletion(String businessId) async {
    final purgeAfter = DateTime.now().add(const Duration(days: 30));
    await _db.collection('config').doc(businessId).set({
      'status': 'pending_deletion',
      'deletionRequestedAt': FieldValue.serverTimestamp(),
      'deletionScheduledAt': Timestamp.fromDate(purgeAfter),
      'deletionRequestedByUid': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
    await signOut();
  }

  /// Cancels a pending deletion — called when the owner logs back in during the
  /// 30-day grace window and chooses to keep their account.
  Future<void> cancelAccountDeletion(String businessId) async {
    await _db.collection('config').doc(businessId).update({
      'status': FieldValue.delete(),
      'deletionRequestedAt': FieldValue.delete(),
      'deletionScheduledAt': FieldValue.delete(),
      'deletionRequestedByUid': FieldValue.delete(),
    });
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
