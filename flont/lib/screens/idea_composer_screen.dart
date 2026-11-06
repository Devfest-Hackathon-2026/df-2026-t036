import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
  const IdeaComposerScreen({super.key, required this.onSubmit});

  final Future<void> Function(IdeaDraft draft) onSubmit;

  @override
  State<IdeaComposerScreen> createState() => _IdeaComposerScreenState();
}

class _IdeaComposerScreenState extends State<IdeaComposerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final List<String> _tags = [];
  bool _showPreview = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    if (tag.runes.length > 20) {
      setState(() => _error = 'タグは20文字以内で入力してください。');
      return;
    }
    if (!_tags.contains(tag) && _tags.length >= 5) {
      setState(() => _error = 'タグは5個まで追加できます。');
      return;
    }
    setState(() {
      if (!_tags.contains(tag)) _tags.add(tag);
      _tagController.clear();
      _error = null;
    });
  }

  void _showConfirmation() {
    if (!_formKey.currentState!.validate()) return;
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
    return Scaffold(
      appBar: AppBar(title: Text(_showPreview ? '投稿内容の確認' : 'アイデアを作成')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
          Text('タグ（任意・最大5個）', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('idea-tag-input'),
                  controller: _tagController,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTag(),
                  decoration: const InputDecoration(
                    labelText: 'タグ',
                    hintText: '例：ファンタジー',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('idea-add-tag'),
                tooltip: 'タグを追加',
                onPressed: _addTag,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
              ],
            ),
          ],
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

  Widget _buildPreview(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
