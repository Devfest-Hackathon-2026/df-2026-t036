import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Session-local LRU of encoded images. Never writes files or browser storage.
/// Decoded images remain subject to Flutter's separate ImageCache limit.
class ArtworkImageCache {
  ArtworkImageCache({
    this.maxBytes = 32 * 1024 * 1024,
    this.maxEntries = 8,
    this.maxAge = const Duration(minutes: 3),
    DateTime Function()? now,
  }) : assert(maxBytes > 0),
       assert(maxEntries > 0),
       assert(maxAge > Duration.zero),
       _now = now ?? DateTime.now;

  final int maxBytes;
  final int maxEntries;
  final Duration maxAge;
  final DateTime Function() _now;
  final _entries = <String, _CachedImage>{};
  final _pending = <String, Future<Uint8List>>{};
  int _bytes = 0;

  Future<Uint8List> load(
    String id, {
    required Future<Uint8List> Function() loader,
    DateTime? expiresAt,
  }) {
    prune();
    if (expiresAt != null && !expiresAt.isAfter(_now())) {
      remove(id);
      return Future.error(StateError('Artwork has expired'));
    }
    final cached = _entries.remove(id);
    if (cached != null) {
      // Reinsert at the end: eviction removes the least recently used item.
      _entries[id] = cached;
      return Future.value(cached.bytes);
    }
    final pending = _pending[id];
    if (pending != null) return pending;
    final ttl = _now().add(maxAge);
    final validUntil = expiresAt != null && expiresAt.isBefore(ttl)
        ? expiresAt
        : ttl;
    late final Future<Uint8List> request;
    request = Future<Uint8List>.sync(loader)
        .then((bytes) {
          // Invalidated requests may finish, but cannot repopulate or serve a new session.
          if (!identical(_pending[id], request) ||
              !validUntil.isAfter(_now())) {
            throw StateError('Artwork image request is no longer valid');
          }
          if (bytes.isEmpty) throw StateError('Empty artwork image');
          if (bytes.lengthInBytes <= maxBytes) {
            while (_entries.isNotEmpty &&
                (_bytes + bytes.lengthInBytes > maxBytes ||
                    _entries.length >= maxEntries)) {
              remove(_entries.keys.first);
            }
            _entries[id] = _CachedImage(bytes, validUntil);
            _bytes += bytes.lengthInBytes;
          }
          return bytes;
        })
        .whenComplete(() {
          if (identical(_pending[id], request)) _pending.remove(id);
        });
    _pending[id] = request;
    return request;
  }

  void prune() {
    for (final id in _entries.keys.toList()) {
      if (!_entries[id]!.validUntil.isAfter(_now())) remove(id);
    }
  }

  /// Use only after a successful list response, never after a transient error.
  void retain(Set<String> ids) {
    for (final id in {..._entries.keys, ..._pending.keys}) {
      if (!ids.contains(id)) remove(id);
    }
    prune();
  }

  void remove(String id) {
    _pending.remove(id);
    final image = _entries.remove(id);
    if (image != null) {
      _bytes -= image.bytes.lengthInBytes;
      unawaited(MemoryImage(image.bytes).evict());
    }
  }

  void clear() {
    for (final id in {..._entries.keys, ..._pending.keys}) {
      remove(id);
    }
  }
}

class _CachedImage {
  const _CachedImage(this.bytes, this.validUntil);
  final Uint8List bytes;
  final DateTime validUntil;
}
