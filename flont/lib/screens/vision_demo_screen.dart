import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class VisionDemoScreen extends StatefulWidget {
  const VisionDemoScreen({
    super.key,
    required this.apiBaseUrl,
    this.client,
    this.idTokenProvider,
    this.imagePicker,
  });

  final String apiBaseUrl;
  // 通信・認証・画像選択を差し替え、画面離脱やタイムアウトを検証する。
  final http.Client? client;
  final Future<String?> Function()? idTokenProvider;
  final Future<XFile?> Function()? imagePicker;

  @override
  State<VisionDemoScreen> createState() => _VisionDemoScreenState();
}

class _VisionDemoScreenState extends State<VisionDemoScreen> {
  Uint8List? _imageBytes;
  bool _picking = false;
  String? _fileName;
  Map<String, dynamic>? _categories;
  String? _error;
  bool _busy = false;

  // 選択ダイアログと選択後の検証で、対応拡張子を共有する。
  static const _allowedExtensions = ['jpg', 'jpeg', 'png', 'heic', 'heif'];
  static const _maxImageBytes = 20 * 1024 * 1024;

  static const _labels = {
    'adult': '成人向け表現',
    'spoof': '風刺・模倣',
    'medical': '医療表現',
    'violence': '暴力表現',
    'racy': '刺激の強い表現',
  };

  Future<void> _chooseImage() async {
    if (_picking || _busy) return;
    setState(() => _picking = true);
    try {
      final file = widget.imagePicker != null
          ? await widget.imagePicker!()
          : await openFile(
              acceptedTypeGroups: const [
                XTypeGroup(
                  label: '画像',
                  extensions: _allowedExtensions,
                  mimeTypes: [
                    'image/jpeg',
                    'image/png',
                    'image/heic',
                    'image/heif',
                  ],
                  uniformTypeIdentifiers: [
                    'public.jpeg',
                    'public.png',
                    'public.heic',
                    'public.heif',
                  ],
                ),
              ],
            );
      // ファイル選択中に画面を閉じた場合は表示を更新しない。
      if (!mounted || file == null) return;
      // OSの選択フィルターを通り抜けた非対応形式も送信しない。
      if (!_allowedExtensions.contains(
        file.name.split('.').last.toLowerCase(),
      )) {
        throw StateError('JPEG、PNG、HEIC/HEIFの画像を選んでください。');
      }
      // 大きなファイルは全体をメモリーへ読み込む前に拒否する。
      final length = await file.length();
      if (!mounted) return;
      if (length > _maxImageBytes) {
        throw StateError('画像は20MB以下のものを選んでください。');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        throw StateError('画像を読み込めませんでした。別の画像を選んでください。');
      }
      // 申告された容量と実データが異なる場合も検証する。
      if (bytes.length > _maxImageBytes) {
        throw StateError('画像は20MB以下のものを選んでください。');
      }
      setState(() {
        _imageBytes = bytes;
        _fileName = file.name;
        _categories = null;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is StateError
            ? error.message.toString()
            : '画像を選択できませんでした。もう一度お試しください。',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _analyze() async {
    final bytes = _imageBytes;
    if (bytes == null || _busy || _picking) return;
    setState(() {
      _busy = true;
      _error = null;
      _categories = null;
    });
    final client = widget.client ?? http.Client();
    try {
      final token = widget.idTokenProvider != null
          ? await widget.idTokenProvider!()
          : await FirebaseAuth.instance.currentUser?.getIdToken();
      if (!mounted) return;
      if (token == null) throw StateError('ログイン状態を確認できません。再度ログインしてください。');

      final uri = Uri.parse(
        '${widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/v1/vision-demo',
      );
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: _fileName ?? 'image',
          ),
        );
      // ヘッダーだけでなく本文を受け取るまでを90秒以内に制限する。
      final response = await (() async {
        final streamed = await client.send(request);
        return await http.Response.fromStream(streamed);
      })().timeout(const Duration(seconds: 90));
      if (!mounted) return;
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
      // この画面が生成した通信クライアントはタイムアウト時も解放する。
      if (widget.client == null) client.close();
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
                onPressed: _busy || _picking ? null : _chooseImage,
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
                    // 未使用の引数はワイルドカードで受け取る。
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('プレビューを表示できません')),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || _picking ? null : _analyze,
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
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
