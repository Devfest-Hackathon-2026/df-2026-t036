import 'package:flutter/material.dart';

import '../theme/page_layout.dart';

/// Keeps content in place while showing progress in the shared gap.
class PageLoadingGap extends StatelessWidget {
  const PageLoadingGap({super.key, required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: PageLayout.verticalGap,
    child: Center(
      child: loading ? const LinearProgressIndicator(minHeight: 2) : null,
    ),
  );
}
