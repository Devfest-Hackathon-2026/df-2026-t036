import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'screens/main_screen.dart';
import 'config/app_config.dart';
import 'screens/login_screen.dart';

/// GoogleログインとAPI側の登録が両方成功してからメイン画面を表示する。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _subscription;
  FirebaseAuth? _auth;
  String _apiBaseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  Map<String, dynamic>? _me;
  String? _error;
  bool _busy = true;
  bool _ready = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Webでは引数なしのflutter runでもローカルの公開設定を読み込む。
      if (kIsWeb) {
        final config = await AppConfig.load();
        _apiBaseUrl = config.apiBaseUrl;
        await Firebase.initializeApp(options: config.firebaseOptions);
      } else {
        await Firebase.initializeApp();
      }
      if (!mounted) return;
      _auth = FirebaseAuth.instance;
      _ready = true;
      // 再読み込み時にも復元されたログイン状態で登録APIを再実行する。
      _subscription = _auth!.authStateChanges().listen(_onUserChanged);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is StateError
            ? error.message.toString()
            : 'Firebaseを初期化できませんでした。設定を確認して再読み込みしてください。';
      });
    }
  }

  void _onUserChanged(User? user) {
    final generation = ++_generation;
    setState(() {
      _me = null;
      _error = null;
      _busy = user != null;
    });
    if (user != null) _register(user, generation);
  }

  Future<void> _register(User user, int generation) async {
    try {
      final token = await user.getIdToken();
      if (token == null) throw StateError('認証情報を取得できませんでした。');
      final base = _apiBaseUrl;
      final response = await http
          .post(
            Uri.parse(
              '${base.replaceFirst(RegExp(r'/+$'), '')}/api/v1/users/register',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 && response.statusCode != 201) {
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        throw StateError(
          (body['error'] as Map<String, dynamic>)['message'] as String,
        );
      }
      final me =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (!mounted || generation != _generation) return;
      setState(() {
        _me = me;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = error is StateError
            ? error.message.toString()
            : 'ユーザー登録に失敗しました。接続を確認して再試行してください。';
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await _auth!.signInWithPopup(provider);
      } else {
        await _auth!.signInWithProvider(provider);
      }
      // 以降の登録は認証状態の通知から一度だけ開始する。
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'popup-closed-by-user'
            ? 'ログインをキャンセルしました。'
            : 'Googleログインに失敗しました。再試行してください。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'ログインに失敗しました。再試行してください。';
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_me != null) {
      return MainScreen(
        me: _me,
        googleEmail: _auth?.currentUser?.email,
        apiBaseUrl: _apiBaseUrl,
      );
    }
    // APIが返した既存のDB情報を取得できた場合にだけメイン画面へ進む。
    return LoginScreen(
      busy: _busy,
      error: _error,
      hasAccount: _auth?.currentUser != null,
      onSignIn: !_ready
          ? null
          : () {
              final user = _auth!.currentUser;
              if (user == null) {
                _signIn();
              } else {
                _onUserChanged(user);
              }
            },
      onSignOut: _ready ? () => _auth!.signOut() : null,
    );
  }
}
