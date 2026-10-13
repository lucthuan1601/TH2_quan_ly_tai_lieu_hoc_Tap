import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    firebase_auth.FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? firebase_auth.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final firebase_auth.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  Future<void> initialize() => _googleSignIn.initialize();

  Stream<AuthUser?> get userChanges => _auth.authStateChanges().map(
        (user) => user == null
            ? null
            : AuthUser(
                id: user.uid, email: user.email, displayName: user.displayName),
      );

  Future<AuthUser> signInWithGoogle() async {
    final account = await _googleSignIn.authenticate();
    final authentication = account.authentication;
    final credential = firebase_auth.GoogleAuthProvider.credential(
      idToken: authentication.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
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
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }
}

class AuthUser {
  const AuthUser({required this.id, this.email, this.displayName});

  final String id;
  final String? email;
  final String? displayName;
}
