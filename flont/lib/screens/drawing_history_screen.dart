import 'history_screen.dart';

class DrawingHistoryScreen extends HistoryScreen {
  const DrawingHistoryScreen({
    super.key,
    super.apiBaseUrl,
    super.authenticated,
    super.client,
    super.idTokenProvider,
  }) : super(kind: HistoryKind.drawings);
}
