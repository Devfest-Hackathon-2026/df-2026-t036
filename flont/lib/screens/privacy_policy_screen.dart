import 'package:flutter/material.dart';

import 'terms_screen.dart';

/// 文書原本を直接読み込み、閲覧を同意取得として扱わない。
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => const TermsScreen(
    title: 'プライバシーポリシー v0（草案）',
    assetPath: '../docs/legal/privacy-policy-v0.md',
  );
}
