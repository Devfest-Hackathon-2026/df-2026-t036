import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/page_layout.dart';

class IdeaDraft {
  const IdeaDraft({
    required this.title,
    required this.description,
    required this.tags,
  });

  final String title;
  final String description;
  final List<String> tags;
}

class IdeaComposerScreen extends StatefulWidget {
  const IdeaComposerScreen({
    super.key,
    required this.onSubmit,
    this.loadTagSuggestions,
  });

  final Future<void> Function(IdeaDraft draft) onSubmit;
  final Future<List<String>> Function()? loadTagSuggestions;

  @override
  State<IdeaComposerScreen> createState() => _IdeaComposerScreenState();
}

class _IdeaComposerScreenState extends State<IdeaComposerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final List<String> _tags = [];
  List<String> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _suggestionsFailed = false;
  String? _tagError;
  bool _showPreview = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tagController.addListener(_onTagChanged);
    _loadSuggestions();
  }

  void _onTagChanged() => setState(() => _tagError = null);

  Future<void> _loadSuggestions() async {
    final load = widget.loadTagSuggestions;
    if (load == null || _loadingSuggestions) return;
    setState(() {
      _loadingSuggestions = true;
      _suggestionsFailed = false;
    });
    try {
      final tags = await load();
      if (!mounted) return;
      setState(() {
        _suggestions =
            tags
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty && tag.runes.length <= 20)
                .toSet()
                .toList()
              ..sort();
      });
    } catch (_) {
      if (mounted) setState(() => _suggestionsFailed = true);
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.removeListener(_onTagChanged);
    _tagController.dispose();
    super.dispose();
  }

  bool _addTag([String? suggestion]) {
    final tag = (suggestion ?? _tagController.text).trim();
    if (tag.isEmpty) return true;
    if (tag.runes.length > 20) {
      setState(() => _tagError = 'タグは20文字以内で入力してください。');
      return false;
    }
    if (!_tags.contains(tag) && _tags.length >= 5) {
      setState(() => _tagError = 'タグは5個まで追加できます。');
      return false;
    }
    setState(() {
      if (!_tags.contains(tag)) _tags.add(tag);
      _tagController.clear();
      _tagError = null;
    });
    return true;
  }

  void _showConfirmation() {
    if (!_formKey.currentState!.validate()) return;
    if (!_addTag()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _showPreview = true;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        IdeaDraft(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          tags: List.unmodifiable(_tags),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error is StateError
              ? error.message.toString()
              : '投稿できませんでした。入力内容と接続を確認して再試行してください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 入力と投稿前確認を、一覧・詳細と同じ共通幅にそろえる。
    final layout = PageLayout.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_showPreview ? '投稿内容の確認' : 'アイデアを作成')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.bodyWidth),
            child: _showPreview ? _buildPreview(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: PageLayout.of(context).insets,
        children: [
          Text('描いてほしいアイデア', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'タイトルと内容を入力してください。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const ValueKey('idea-title-input'),
            controller: _titleController,
            maxLength: 40,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'タイトル',
              hintText: '例：雨の日の小さな喫茶店',
            ),
            validator: (value) {
              final title = value?.trim() ?? '';
              if (title.isEmpty) return 'タイトルを入力してください。';
              if (title.runes.length > 40) return 'タイトルは40文字以内です。';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('idea-description-input'),
            controller: _descriptionController,
            maxLength: 600,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'アイデアの内容',
              hintText: '描いてほしい情景や雰囲気を書いてください',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              final description = value?.trim() ?? '';
              if (description.isEmpty) return '内容を入力してください。';
              if (description.runes.length > 600) {
                return '内容は600文字以内です。';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildTagInput(context),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('idea-preview-button'),
            onPressed: _showConfirmation,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('内容を確認する'),
          ),
        ],
      ),
    );
  }

  Widget _buildTagInput(BuildContext context) {
    final input = _tagController.text.trim();
    final candidates = _suggestions
        .where(
          (tag) =>
              !_tags.contains(tag) && (input.isEmpty || tag.contains(input)),
        )
        .take(8)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'タグ（任意） (${_tags.length} / 5)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(() {
                    _tags.remove(tag);
                    _tagError = null;
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('idea-tag-input'),
          controller: _tagController,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            final composing = _tagController.value.composing;
            if (!composing.isValid || composing.isCollapsed) _addTag();
          },
          decoration: InputDecoration(
            labelText: 'タグを入力',
            hintText: '例：ファンタジー',
            counterText: '',
            helperText: '候補をタップ、または入力して追加',
            errorText: _tagError,
          ),
        ),
        if (input.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('idea-add-tag'),
            onPressed: () => _addTag(),
            icon: const Icon(Icons.add),
            label: Text('「$input」を追加'),
          ),
        ],
        if (_loadingSuggestions) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_suggestionsFailed)
          TextButton.icon(
            onPressed: _loadSuggestions,
            icon: const Icon(Icons.refresh),
            label: const Text('候補を再読み込み'),
          ),
        if (candidates.isNotEmpty && _tags.length < 5) ...[
          const SizedBox(height: 8),
          Text('使われているタグ', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in candidates)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(tag),
                  onPressed: () => _addTag(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    return ListView(
      padding: PageLayout.of(context).insets,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleController.text.trim(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(_descriptionController.text.trim()),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [for (final tag in _tags) Chip(label: Text(tag))],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '投稿後は内容を編集できません。',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('idea-submit-button'),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(_submitting ? '投稿中…' : '投稿する'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _submitting
              ? null
              : () => setState(() => _showPreview = false),
          icon: const Icon(Icons.arrow_back),
          label: const Text('内容を修正する'),
        ),
      ],
    );
  }
}
