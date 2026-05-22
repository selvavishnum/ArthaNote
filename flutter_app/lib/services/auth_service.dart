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

  /// Looks up a staff document by email — used to link a new Firebase UID
  /// to an existing account's businessId when UIDs differ across auth methods.
  /// [skipUid] — prefer docs whose businessId is NOT this uid (i.e. the original account).
  Future<Map<String, dynamic>?> getProfileByEmail(String email,
      {String skipUid = ''}) async {
    final snap = await _db
        .collection('staff')
        .where('email', isEqualTo: email)
        .limit(5)
        .get();
    // First pass: prefer doc where businessId differs from the current uid
    // (that doc is the original account, not the newly-created duplicate)
    if (skipUid.isNotEmpty) {
      for (final doc in snap.docs) {
        final bid = doc.data()['businessId'] as String?;
        if (bid != null && bid.isNotEmpty && bid != skipUid) return doc.data();
      }
    }
    // Second pass: any doc with a non-empty businessId
    for (final doc in snap.docs) {
      final bid = doc.data()['businessId'] as String?;
      if (bid != null && bid.isNotEmpty) return doc.data();
    }
    return snap.docs.isNotEmpty ? snap.docs.first.data() : null;
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
}
