import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowling_diary/features/auth/domain/entities/user_entity.dart';
import 'package:bowling_diary/features/auth/data/models/user_model.dart';

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

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
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
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (data) {
        final d = data as dynamic;
        handleAuthStateChange(d.event as AuthChangeEvent, d.session as Session?);
      },
    );
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

  Future<void> signInWithGoogle() async {
    state = AuthStateLoading();
    try {
      await _supabase.auth.signInWithOAuth(OAuthProvider.google);
    } catch (e) {
      state = AuthStateError('Google 로그인에 실패했습니다');
    }
  }

  Future<void> signInWithApple() async {
    state = AuthStateLoading();
    try {
      await _supabase.auth.signInWithOAuth(OAuthProvider.apple);
    } catch (e) {
      state = AuthStateError('Apple 로그인에 실패했습니다');
    }
  }

  Future<void> signInWithKakao() async {
    state = AuthStateLoading();
    try {
      await _supabase.auth.signInWithOAuth(OAuthProvider.kakao);
    } catch (e) {
      state = AuthStateError('카카오 로그인에 실패했습니다');
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

  void handleAuthStateChange(AuthChangeEvent event, Session? session) {
    if (event == AuthChangeEvent.signedIn && session != null) {
      _loadUserProfile(session.user.id);
    } else if (event == AuthChangeEvent.signedOut) {
      state = AuthStateUnauthenticated();
    }
  }
}
