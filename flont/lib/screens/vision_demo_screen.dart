import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class VisionDemoScreen extends StatefulWidget {
  const VisionDemoScreen({super.key, required this.apiBaseUrl});

  final String apiBaseUrl;

  @override
  State<VisionDemoScreen> createState() => _VisionDemoScreenState();
}

class _VisionDemoScreenState extends State<VisionDemoScreen> {
  Uint8List? _imageBytes;
  String? _fileName;
  Map<String, dynamic>? _categories;
  String? _error;
  bool _busy = false;

  static const _labels = {
    'adult': '成人向け表現',
    'spoof': '風刺・模倣',
    'medical': '医療表現',
    'violence': '暴力表現',
    'racy': '刺激の強い表現',
  };

  Future<void> _chooseImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = '画像を読み込めませんでした。別の画像を選んでください。');
      return;
    }
    if (bytes.length > 20 * 1024 * 1024) {
      setState(() => _error = '画像は20MB以下のものを選んでください。');
      return;
    }
    setState(() {
      _imageBytes = bytes;
      _fileName = file.name;
      _categories = null;
      _error = null;
    });
  }

  Future<void> _analyze() async {
    final bytes = _imageBytes;
    if (bytes == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _categories = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();
      if (token == null) throw StateError('ログイン状態を確認できません。再度ログインしてください。');

      final uri = Uri.parse(
        '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/vision-demo',
      );
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _fileName ?? 'image',
        ));
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final error = body['error'] as Map<String, dynamic>?;
        throw StateError(error?['message'] as String? ?? '画像を判定できませんでした。');
      }
      setState(() => _categories = body['categories'] as Map<String, dynamic>?);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : '判定に失敗しました。接続を確認してもう一度お試しください。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vision API デモ')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '画像を選ぶと、Google Cloud Vision APIが5つの項目を判定します。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_fileName ?? '画像を選択'),
              ),
              if (_imageBytes != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 280,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('プレビューを表示できません')),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _analyze,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_busy ? '判定しています…' : '判定する'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_categories != null) ...[
                const SizedBox(height: 24),
                Text('判定結果', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final entry in _labels.entries)
                  Card(
                    child: ListTile(
                      title: Text(entry.value),
                      trailing: Text(
                        _categories![entry.key]?.toString() ?? '不明',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'これはデモ結果です。投稿の許可・拒否を確定する機能ではありません。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
