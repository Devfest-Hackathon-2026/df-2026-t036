import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'page_loading_gap.dart';

class FontLoadingGate extends StatefulWidget {
  const FontLoadingGate({super.key, required this.child, this.loadFonts});

  final Widget child;
  final Future<void> Function()? loadFonts;

  @override
  State<FontLoadingGate> createState() => _FontLoadingGateState();
}

class _FontLoadingGateState extends State<FontLoadingGate> {
  late Future<void> _ready;
  bool _useFallback = false;
  bool _contentMounted = false;
  bool _contentReady = false;
  bool _revealScheduled = false;

  static Future<void> _loadFonts() async {
    // The theme uses the regular font family for all text weights.
    // Wait only for that font, rather than downloading unused variants.
    GoogleFonts.mPlusRounded1c();
    await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 8));
  }

  @override
  void initState() {
    super.initState();
    _ready = (widget.loadFonts ?? _loadFonts)();
    // Show the loading frame before starting the hidden page's construction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _contentMounted = true);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      final fontsReady =
          _useFallback ||
          (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError);
      if (fontsReady && _contentMounted && !_revealScheduled) {
        _revealScheduled = true;
        // Complete layout with the loaded font before removing the overlay.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _contentReady = true);
        });
      }
      final showContent = fontsReady && _contentReady;
      final failed =
          snapshot.connectionState == ConnectionState.done && snapshot.hasError;
      final loadingScreen = Scaffold(
        appBar: AppBar(
          title: Image.asset(
            'assets/images/logo.png',
            width: 120,
            height: 52,
            fit: BoxFit.contain,
            semanticLabel: 'EWOCURU',
          ),
        ),
        body: Column(
          children: [
            PageLoadingGap(loading: !failed),
            if (failed)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'フォントを読み込めませんでした。',
                          textAlign: TextAlign.center,
                          // The loading message itself must not require the web font.
                          style: const TextStyle(
                            fontFamily: 'sans-serif',
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                        if (failed) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => setState(() {
                              _ready = (widget.loadFonts ?? _loadFonts)();
                            }),
                            child: const Text('再試行'),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _useFallback = true),
                            child: const Text('そのまま続ける'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_contentMounted)
            Offstage(
              offstage: !showContent,
              child: TickerMode(
                enabled: showContent,
                child: ExcludeFocus(
                  excluding: !showContent,
                  child: widget.child,
                ),
              ),
            ),
          if (!showContent) loadingScreen,
        ],
      );
    },
  );
}
