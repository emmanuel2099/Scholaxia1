import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseOtpSendResult {
  final bool codeSent;
  final String? idToken; // set when Android auto-verifies

  const FirebaseOtpSendResult.codeSent()
      : codeSent = true,
        idToken = null;

  const FirebaseOtpSendResult.autoVerified(this.idToken)
      : codeSent = false;
}

/// Firebase Phone Auth helpers (Android / iOS).
class FirebasePhoneAuthService {
  FirebasePhoneAuthService._();
  static final FirebasePhoneAuthService instance = FirebasePhoneAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _verificationId;
  int? _resendToken;

  /// Convert local NG numbers to E.164 (+234...).
  static String normalizePhone(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    if (s.startsWith('+')) return s;
    if (s.startsWith('0') && s.length == 11) return '+234${s.substring(1)}';
    if (s.length == 10) return '+234$s';
    if (s.startsWith('234')) return '+$s';
    return s.startsWith('+') ? s : '+$s';
  }

  Future<void> _ensureFirebase() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  /// Send SMS OTP via Firebase.
  Future<FirebaseOtpSendResult> sendOtp(String phoneRaw) async {
    if (kIsWeb) {
      throw StateError('Firebase Phone Auth works on Android/iOS only.');
    }
    await _ensureFirebase();
    final phone = normalizePhone(phoneRaw);
    final completer = Completer<FirebaseOtpSendResult>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 90),
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final cred = await _auth.signInWithCredential(credential);
          final token = await cred.user?.getIdToken(true);
          if (token != null && token.isNotEmpty && !completer.isCompleted) {
            completer.complete(FirebaseOtpSendResult.autoVerified(token));
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(e.message ?? 'SMS verification failed (${e.code})'),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!completer.isCompleted) {
          completer.complete(const FirebaseOtpSendResult.codeSent());
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 100),
      onTimeout: () => throw StateError(
        'Timed out waiting for SMS. Check the number and try again.',
      ),
    );
  }

  /// Confirm SMS code and return Firebase ID token.
  Future<String> confirmOtp(String smsCode) async {
    await _ensureFirebase();
    final vid = _verificationId;
    if (vid == null || vid.isEmpty) {
      throw StateError('No verification in progress. Send OTP first.');
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: vid,
      smsCode: smsCode.trim(),
    );
    final cred = await _auth.signInWithCredential(credential);
    final token = await cred.user?.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Could not get Firebase ID token.');
    }
    return token;
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
