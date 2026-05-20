import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> registerEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<UserCredential?> signInGoogle() async {
    final account = await GoogleSignIn().signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    return _auth.signInWithCredential(cred);
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('staff').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> saveProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('staff').doc(uid).set(data, SetOptions(merge: true));

  Future<Map<String, dynamic>?> getConfig(String businessId) async {
    final doc = await _db.collection('config').doc(businessId).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> saveConfig(String businessId, Map<String, dynamic> data) =>
      _db.collection('config').doc(businessId).set(data, SetOptions(merge: true));
}
