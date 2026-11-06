import 'package:flutter/material.dart';

/// 新規登録とログインの状態を表示する画面。
class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    this.onSignIn,
    this.onSignOut,
    this.busy = false,
    this.error,
    this.hasAccount = false,
  });

  // 認証処理はAuthGateに任せ、画面には操作と状態を渡す。
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;
  final bool busy;
  final String? error;
  final bool hasAccount;

  static const _ink = Color(0xFF303650);
  static const _accent = Color(0xFF6465AD);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 小さい画面ではスクロールでき、広い画面では中央に配置する。
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome_outlined,
                              color: _accent,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Illustration Exchange',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 44),
                        // 外部画像を使わず、お題と作品の交換をカードで表現する。
                        const _ExchangeArtwork(),
                        const SizedBox(height: 32),
                        const Text(
                          'だれかの「描いて」を、\nあなたの一枚に。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ink,
                            fontSize: 28,
                            height: 1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'お題を見つけて、描いて、届ける。\nイラストでつながる、小さな創作の場所。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF74768B),
                            fontSize: 14,
                            height: 1.9,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFE8E6F1)),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                '創作をはじめよう',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '初回は新規登録。登録済みの方は同じGoogleアカウントで。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF74768B),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  // 処理中は重複して認証を開始しない。
                                  onPressed: busy ? null : onSignIn,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.login_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    busy
                                        ? '接続中…'
                                        : hasAccount
                                        ? 'ユーザー情報の取得を再試行'
                                        : 'Googleで新規登録・ログイン',
                                  ),
                                ),
                              ),
                              // 通信状況を表示し、失敗時は再試行やアカウント変更を可能にする。
                              if (busy) ...[
                                const SizedBox(height: 16),
                                const LinearProgressIndicator(
                                  semanticsLabel: 'アカウント情報を読み込み中',
                                ),
                              ],
                              if (error != null) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                              if (hasAccount && onSignOut != null)
                                TextButton(
                                  onPressed: busy ? null : onSignOut,
                                  child: const Text('別のアカウントでログイン'),
                                ),
                              const SizedBox(height: 12),
                              const Text(
                                'ログイン後は保存済みのプロフィールを表示します。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF74768B),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 16,
                                    color: Color(0xFF8C8B9E),
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '表示名は自動で作成されます。\nGoogleの本名は公開されません。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF8C8B9E),
                                        fontSize: 11,
                                        height: 1.7,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'つづけることで、利用規約と\nプライバシーポリシーに同意したものとします。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8C8B9E),
                            fontSize: 11,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'ひとつのお題から、あたらしいつながり。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8C8B9E),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 装飾用カードは画面幅に合わせて縮小し、読み上げの対象から外す。
class _ExchangeArtwork extends StatelessWidget {
  const _ExchangeArtwork();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 162,
        child: FittedBox(
          child: SizedBox(
            width: 300,
            height: 162,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 20,
                  top: 12,
                  child: Transform.rotate(
                    angle: -0.13,
                    child: _card(
                      const Color(0xFFEBE8FA),
                      Icons.lightbulb_outline_rounded,
                      '小さなひらめき',
                      const Color(0xFF7771B8),
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: 20,
                  child: Transform.rotate(
                    angle: 0.12,
                    child: _card(
                      const Color(0xFFFBE8DF),
                      Icons.palette_outlined,
                      'あなたの一枚',
                      const Color(0xFFC18369),
                    ),
                  ),
                ),
                const Positioned(
                  top: 69,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: LoginScreen._accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(
    Color background,
    IconData icon,
    String caption,
    Color foreground,
  ) {
    return Container(
      width: 126,
      height: 132,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D303650),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 42, color: foreground),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: const TextStyle(fontSize: 10, color: LoginScreen._ink),
          ),
        ],
      ),
    );
  }
}
