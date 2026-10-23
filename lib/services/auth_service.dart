import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    firebase_auth.FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? firebase_auth.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final firebase_auth.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  // google_sign_in cannot sign in on web (the SDK only allows its own button),
  // so web uses Firebase's popup flow instead.
  Future<void> initialize() async {
    if (!kIsWeb) await _googleSignIn.initialize();
  }

  Stream<AuthUser?> get userChanges => _auth.authStateChanges().map(
        (user) => user == null
            ? null
            : AuthUser(
                id: user.uid, email: user.email, displayName: user.displayName),
      );

  Future<AuthUser> signInWithGoogle() async {
    if (kIsWeb) {
      final result =
          await _auth.signInWithPopup(firebase_auth.GoogleAuthProvider());
      return _toAuthUser(result);
    }
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google không trả về ID token để đăng nhập Firebase.');
    }
    return _toAuthUser(await _auth.signInWithCredential(
      firebase_auth.GoogleAuthProvider.credential(idToken: idToken),
    ));
  }

  AuthUser _toAuthUser(firebase_auth.UserCredential result) {
    final user = result.user;
    if (user == null) {
      throw StateError('Firebase không trả về thông tin tài khoản.');
    }
    return AuthUser(
      id: user.uid,
      email: user.email,
      displayName: user.displayName,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) await _googleSignIn.signOut();
  }
}

class AuthUser {
  const AuthUser({required this.id, this.email, this.displayName});

  final String id;
  final String? email;
  final String? displayName;
}
