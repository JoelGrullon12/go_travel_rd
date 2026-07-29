import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user.dart';
import 'firebase_config.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _firestore = firestore;

  AuthService() {
    _initGoogleSignIn();
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await GoogleSignIn.instance.initialize();
    } catch (_) {}
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<AppUser?> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _getUserData(cred.user!.uid);
  }

  Future<AppUser?> registerWithEmail(
      String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = AppUser(
      uid: cred.user!.uid,
      email: email,
      name: name,
    );
    await _firestore.collection('users').doc(cred.user!.uid).set(user.toMap());
    await cred.user!.updateDisplayName(name);
    return user;
  }

  Future<AppUser?> signInWithGoogle() async {
    GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    final userDoc =
        await _firestore.collection('users').doc(cred.user!.uid).get();

    if (!userDoc.exists) {
      final appUser = AppUser(
        uid: cred.user!.uid,
        email: cred.user!.email ?? '',
        name: cred.user!.displayName ?? '',
        photoUrl: cred.user!.photoURL,
      );
      await _firestore
          .collection('users')
          .doc(cred.user!.uid)
          .set(appUser.toMap());
      return appUser;
    }

    return _getUserData(cred.user!.uid);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  Future<AppUser?> _getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.data()!, uid);
  }

  Future<AppUser?> getUserData(String uid) => _getUserData(uid);
}
