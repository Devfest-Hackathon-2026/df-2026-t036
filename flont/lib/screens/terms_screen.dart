import 'package:flutter/material.dart';

import '../theme/page_layout.dart';

/// 同梱した規約本文を表示する。閲覧しただけでは同意済みとして扱わない。
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  Future<String>? _terms;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _terms ??= _loadTerms();
  }

  Future<String> _loadTerms() =>
      DefaultAssetBundle.of(context).loadString('assets/legal/terms-test.md');

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('利用規約')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.bodyWidth),
            child: FutureBuilder<String>(
              future: _terms,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: layout.insets,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('利用規約を読み込めませんでした。'),
                        TextButton(
                          onPressed: () {
                            final retry = _loadTerms();
                            setState(() {
                              _terms = retry;
                            });
                          },
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // 規約の見出しと段落だけを整形し、本文は省略せず選択・コピー可能にする。
                final paragraphs = snapshot.data!.trim().split(
                  RegExp(r'\r?\n\s*\r?\n'),
                );
                return SingleChildScrollView(
                  padding: layout.insets,
                  child: SelectableText.rich(
                    TextSpan(
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
                      children: [
                        for (var index = 0; index < paragraphs.length; index++)
                          TextSpan(
                            text:
                                '${paragraphs[index].replaceFirst(RegExp(r'^#{1,2}\s+'), '')}${index == paragraphs.length - 1 ? '' : '\n\n'}',
                            style: paragraphs[index].startsWith('# ')
                                ? theme.textTheme.headlineSmall?.copyWith(
                                    height: 1.6,
                                  )
                                : paragraphs[index].startsWith('## ')
                                ? theme.textTheme.titleLarge?.copyWith(
                                    height: 1.6,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
