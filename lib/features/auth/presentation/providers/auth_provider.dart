import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bowling_diary/features/auth/data/models/user_model.dart';
import 'package:bowling_diary/features/auth/domain/entities/user_entity.dart';

sealed class AuthState {}

class AuthStateInitial extends AuthState {}

class AuthStateLoading extends AuthState {}

class AuthStateAuthenticated extends AuthState {
  final UserEntity user;
  AuthStateAuthenticated(this.user);
}

class AuthStateUnauthenticated extends AuthState {}

class AuthStateNeedsProfile extends AuthState {
  final String userId;
  AuthStateNeedsProfile(this.userId);
}

class AuthStateError extends AuthState {
  final String message;
  AuthStateError(this.message);
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

final currentUserProvider = Provider<UserEntity?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is AuthStateAuthenticated) return authState.user;
  return null;
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthStateInitial()) {
    _init();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      _handleAuthStateChange(data.event, data.session);
    });
  }

  final _supabase = Supabase.instance.client;
  StreamSubscription<dynamic>? _authSubscription;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    state = AuthStateLoading();
    final session = _supabase.auth.currentSession;
    if (session == null) {
      state = AuthStateUnauthenticated();
      return;
    }
    await _loadUserProfile(session.user.id);
  }

  Future<void> _loadUserProfile(String userId) async {
    try {
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) {
        state = AuthStateNeedsProfile(userId);
      } else {
        final user = UserModel.fromJson(data);
        if (!user.isProfileComplete) {
          state = AuthStateNeedsProfile(userId);
        } else {
          state = AuthStateAuthenticated(user);
        }
      }
    } catch (e) {
      state = AuthStateNeedsProfile(userId);
    }
  }

  // --- Google 네이티브 로그인 ---
  Future<void> signInWithGoogle() async {
    state = AuthStateLoading();
    try {
      // TODO: Google Cloud Console에서 발급받은 Client ID로 교체 필요
      const webClientId = String.fromEnvironment(
        'GOOGLE_WEB_CLIENT_ID',
        defaultValue: '',
      );
      const iosClientId = String.fromEnvironment(
        'GOOGLE_IOS_CLIENT_ID',
        defaultValue: '',
      );

      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        clientId: iosClientId.isNotEmpty ? iosClientId : null,
        serverClientId: webClientId.isNotEmpty ? webClientId : null,
      );

      final googleUser = await googleSignIn.authenticate();

      final idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        state = AuthStateError('Google 인증 토큰을 가져올 수 없습니다');
        return;
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      if (response.session == null) {
        state = AuthStateError('Google 로그인에 실패했습니다');
      }
    } on GoogleSignInException catch (e) {
      debugPrint('Google 로그인 에러: $e');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        state = AuthStateUnauthenticated();
        return;
      }
      state = AuthStateError('Google 로그인에 실패했습니다');
    } catch (e) {
      debugPrint('Google 로그인 에러: $e');
      state = AuthStateError('Google 로그인에 실패했습니다: ${e.toString()}');
    }
  }

  // --- Apple 네이티브 로그인 ---
  Future<void> signInWithApple() async {
    state = AuthStateLoading();
    try {
      final rawNonce = _supabase.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        state = AuthStateError('Apple 인증 토큰을 가져올 수 없습니다');
        return;
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      if (response.session == null) {
        state = AuthStateError('Apple 로그인에 실패했습니다');
      }
    } catch (e) {
      debugPrint('Apple 로그인 에러: $e');
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        state = AuthStateUnauthenticated();
        return;
      }
      state = AuthStateError('Apple 로그인에 실패했습니다: ${e.toString()}');
    }
  }

  Future<void> updateProfile({
    required String nickname,
    required String bowlingStyle,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final now = DateTime.now().toIso8601String();
    await _supabase.from('users').upsert({
      'id': userId,
      'nickname': nickname,
      'bowling_style': bowlingStyle,
      'created_at': now,
    });
    await _loadUserProfile(userId);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    state = AuthStateUnauthenticated();
  }

  Future<void> deleteAccount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('users').delete().eq('id', userId);
    await _supabase.auth.signOut();
    state = AuthStateUnauthenticated();
  }

  void _handleAuthStateChange(AuthChangeEvent event, Session? session) {
    if (event == AuthChangeEvent.signedIn && session != null) {
      _loadUserProfile(session.user.id);
    } else if (event == AuthChangeEvent.signedOut) {
      state = AuthStateUnauthenticated();
    }
  }

}
