import 'package:flutter/material.dart';

import '../theme/page_layout.dart';

const _socialTypes = <String, String>{
  'x': 'X',
  'instagram': 'Instagram',
  'pixiv': 'pixiv',
  'youtube': 'YouTube',
  'other': 'その他',
};

/// 自己紹介・SNSリンクの編集と保存を行う。
class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({
    super.key,
    required this.nickname,
    required this.bio,
    required this.socialLinks,
    required this.onSave,
    this.previewOnly = false,
  });

  final String nickname;
  final String bio;
  final List<Map<String, dynamic>> socialLinks;
  final Future<Map<String, dynamic>> Function(
    String nickname,
    String bio,
    List<Map<String, dynamic>> socialLinks,
  )
  onSave;
  final bool previewOnly;

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  late final TextEditingController _bioController;
  late final List<_SocialLinkDraft> _links;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.nickname);
    _bioController = TextEditingController(text: widget.bio);
    _links = widget.socialLinks
        .map(_SocialLinkDraft.fromMap)
        .toList(growable: true);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  void _addLink() {
    if (_links.length >= 5) return;
    setState(() => _links.add(_SocialLinkDraft()));
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final result = await widget.onSave(
        _nicknameController.text.trim(),
        _bioController.text.trim(),
        _links.map((link) => link.toMap()).toList(growable: false),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = error is StateError
              ? error.message.toString()
              : '保存できませんでした。入力を保ったまま再試行できます。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = PageLayout.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール編集')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.bodyWidth),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: layout.insets,
              children: [
                if (widget.previewOnly)
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.design_services_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('プレビュー用のサンプルです。保存してもサーバーには送信されません。'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('profile-nickname-input'),
                  controller: _nicknameController,
                  enabled: !_saving,
                  maxLength: 24,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'ユーザーネーム',
                    helperText: 'イラストやプロフィールに表示されます',
                  ),
                  validator: (value) {
                    final nickname = value?.trim() ?? '';
                    if (nickname.isEmpty) return 'ユーザーネームを入力してください';
                    if (nickname.length > 24) return '24文字以内で入力してください';
                    if (nickname.runes.any((rune) => rune < 32 || rune == 127)) {
                      return '制御文字は使用できません';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text('自己紹介', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('profile-bio-input'),
                  controller: _bioController,
                  enabled: !_saving,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    hintText: '好きな画材や描いているものを紹介しましょう',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text('SNSリンク', style: theme.textTheme.titleMedium),
                    ),
                    Text(
                      '${_links.length}/5',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_links.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'リンクはまだありません',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                for (var index = 0; index < _links.length; index++)
                  _buildLinkEditor(index, theme),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('profile-link-add'),
                    onPressed: !_saving && _links.length < 5 ? _addLink : null,
                    icon: const Icon(Icons.add_link),
                    label: const Text('リンクを追加'),
                  ),
                ),
                const SizedBox(height: 16),
                if (_saveError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _saveError!,
                    key: const ValueKey('profile-save-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                FilledButton.icon(
                  key: const ValueKey('profile-preview-save'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _saving
                        ? '保存中…'
                        : widget.previewOnly
                        ? 'プレビューに反映'
                        : 'プロフィールを保存',
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('キャンセル'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLinkEditor(int index, ThemeData theme) {
    final draft = _links[index];
    return Card(
      key: ValueKey('profile-link-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.type,
                    decoration: const InputDecoration(labelText: 'SNS'),
                    validator: (_) => null,
                    items: [
                      for (final entry in _socialTypes.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => draft.type = value);
                            }
                          },
                  ),
                ),
                IconButton(
                  tooltip: 'リンクを削除',
                  onPressed: _saving ? null : () => _removeLink(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('profile-link-label-$index'),
              controller: draft.label,
              enabled: !_saving,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: '表示名',
                hintText: '例：作品置き場',
                counterText: '',
              ),
              validator: (value) {
                if (draft.url.text.trim().isEmpty) return null;
                final label = value?.trim() ?? '';
                if (label.isEmpty) return '表示名を入力してください';
                if (label.length > 40) return '表示名は40文字以内です';
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('profile-link-url-$index'),
              controller: draft.url,
              enabled: !_saving,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://',
                prefixIcon: Icon(Icons.link),
              ),
              validator: (value) => _validateLink(index, value),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateLink(int index, String? value) {
    final url = value?.trim() ?? '';
    final draft = _links[index];
    if (url.isEmpty) return 'URLを入力してください（不要なリンクは削除できます）';
    if (url.length > 2048) return 'URLは2048文字以内です';
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      return 'https:// から始まるURLを入力してください';
    }
    const allowedHosts = <String, Set<String>>{
      'x': {'x.com', 'twitter.com'},
      'instagram': {'instagram.com'},
      'pixiv': {'pixiv.net'},
      'youtube': {'youtube.com', 'youtu.be'},
    };
    final hosts = allowedHosts[draft.type];
    if (hosts != null &&
        !hosts.any(
          (host) =>
              parsed.host.toLowerCase() == host ||
              parsed.host.toLowerCase().endsWith('.$host'),
        )) {
      return '${_socialTypes[draft.type]}のURLを入力してください';
    }
    final normalized = url.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
    for (var other = 0; other < _links.length; other++) {
      if (other == index) continue;
      final otherUrl = _links[other].url.text.trim();
      if (otherUrl.isNotEmpty &&
          otherUrl.replaceFirst(RegExp(r'/+$'), '').toLowerCase() ==
              normalized) {
        return '同じURLは複数登録できません';
      }
    }
    return null;
  }
}

class _SocialLinkDraft {
  _SocialLinkDraft({this.type = 'x', String label = '', String url = ''})
    : label = TextEditingController(text: label),
      url = TextEditingController(text: url);

  factory _SocialLinkDraft.fromMap(Map<String, dynamic> value) =>
      _SocialLinkDraft(
        type: _socialTypes.containsKey(value['type'])
            ? value['type'] as String
            : 'other',
        label: value['label'] as String? ?? '',
        url: value['url'] as String? ?? '',
      );

  String type;
  final TextEditingController label;
  final TextEditingController url;

  Map<String, String> toMap() => {
    'type': type,
    'label': label.text.trim().isEmpty
        ? _socialTypes[type]!
        : label.text.trim(),
    'url': url.text.trim(),
  };

  void dispose() {
    label.dispose();
    url.dispose();
  }
}
