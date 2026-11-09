import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:illustration_exchange/services/artwork_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reuses identical bytes until fixed TTL, not extended by hits',
    () async {
      var now = DateTime.utc(2026, 11, 8);
      final cache = ArtworkImageCache(now: () => now);
      var requests = 0;
      Future<Uint8List> loader() async {
        requests++;
        return Uint8List.fromList([1, 2]);
      }

      final first = await cache.load('a', loader: loader);
      now = now.add(const Duration(minutes: 2));
      expect(await cache.load('a', loader: loader), same(first));
      expect(requests, 1);
      now = now.add(const Duration(minutes: 1));
      await cache.load('a', loader: loader);
      expect(requests, 2);
      cache.clear();
    },
  );

  test('artwork expiry overrides TTL', () async {
    var now = DateTime.utc(2026, 11, 8);
    final cache = ArtworkImageCache(now: () => now);
    final expiry = now.add(const Duration(seconds: 20));
    var requests = 0;
    Future<Uint8List> loader() async {
      requests++;
      return Uint8List(2);
    }

    await cache.load('a', expiresAt: expiry, loader: loader);
    now = expiry;
    await expectLater(
      cache.load('a', expiresAt: expiry, loader: loader),
      throwsStateError,
    );
    expect(requests, 1);
    cache.clear();
  });

  test('evicts least recently used images when byte budget is full', () async {
    final cache = ArtworkImageCache(maxBytes: 6);
    final requests = <String, int>{};
    Future<Uint8List> load(String id) => cache.load(
      id,
      loader: () async {
        requests.update(id, (n) => n + 1, ifAbsent: () => 1);
        return Uint8List(3);
      },
    );
    await load('a');
    await load('b');
    await load('a');
    await load('c');
    await load('a');
    await load('b');
    expect(requests, {'a': 1, 'b': 2, 'c': 1});
    cache.clear();
  });

  test('entry limit applies even to small images', () async {
    final cache = ArtworkImageCache(maxEntries: 1);
    var requests = 0;
    Future<Uint8List> loader() async {
      requests++;
      return Uint8List(1);
    }

    await cache.load('a', loader: loader);
    await cache.load('b', loader: loader);
    await cache.load('a', loader: loader);
    expect(requests, 3);
    cache.clear();
  });

  test('oversized image is returned but not retained', () async {
    final cache = ArtworkImageCache(maxBytes: 2);
    var requests = 0;
    Future<Uint8List> loader() async {
      requests++;
      return Uint8List(3);
    }

    expect((await cache.load('a', loader: loader)).length, 3);
    await cache.load('a', loader: loader);
    expect(requests, 2);
  });

  test(
    'concurrent loads share one request and failures remain retryable',
    () async {
      final cache = ArtworkImageCache();
      final loading = Completer<Uint8List>();
      var requests = 0;
      Future<Uint8List> loader() {
        requests++;
        return loading.future;
      }

      final first = cache.load('a', loader: loader);
      final second = cache.load('a', loader: loader);
      expect(first, same(second));
      final firstError = expectLater(first, throwsStateError);
      final secondError = expectLater(second, throwsStateError);
      loading.completeError(StateError('offline'));
      await firstError;
      await secondError;
      await cache.load(
        'a',
        loader: () async {
          requests++;
          return Uint8List(1);
        },
      );
      expect(requests, 2);
      cache.clear();
    },
  );

  test(
    'clear invalidates pending results and the next session refetches',
    () async {
      final cache = ArtworkImageCache();
      final loading = Completer<Uint8List>();
      final first = cache.load('a', loader: () => loading.future);
      final rejected = expectLater(first, throwsStateError);
      cache.clear();
      final fresh = Uint8List.fromList([2]);
      await cache.load('a', loader: () async => fresh);
      loading.complete(Uint8List.fromList([1]));
      await rejected;
      expect(
        await cache.load(
          'a',
          loader: () async => throw StateError('unexpected'),
        ),
        same(fresh),
      );
      cache.clear();
    },
  );

  test('successful list reconciliation evicts missing images', () async {
    final cache = ArtworkImageCache();
    var requests = 0;
    Future<Uint8List> loader() async {
      requests++;
      return Uint8List(1);
    }

    await cache.load('a', loader: loader);
    await cache.load('b', loader: loader);
    cache.retain({'b'});
    await cache.load('b', loader: loader);
    await cache.load('a', loader: loader);
    expect(requests, 3);
    cache.clear();
  });
}
