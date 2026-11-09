import 'history_screen.dart';

class IdeaHistoryScreen extends HistoryScreen {
  const IdeaHistoryScreen({
    super.key,
    super.apiBaseUrl,
    super.authenticated,
    super.client,
    super.idTokenProvider,
  }) : super(kind: HistoryKind.ideas);
}
