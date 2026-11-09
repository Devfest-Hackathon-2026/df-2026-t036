class ReceivedArtwork {
  const ReceivedArtwork({
    required this.title,
    this.submissionId,
    this.artistId,
    this.sourceIdeaId,
    this.readAt,
    this.description,
    this.tags = const [],
    this.artistNickname,
    this.artistProfileAvailable = false,
    this.createdAt,
    this.expiresAt,
    this.liked,
  });

  factory ReceivedArtwork.fromJson(Map<String, dynamic> json) {
    final snapshot = json['sourceIdeaSnapshot'] as Map<String, dynamic>;
    return ReceivedArtwork(
      submissionId: json['submissionId'] as String,
      artistId: json['artistId'] as String?,
      sourceIdeaId: json['sourceIdeaId'] as String,
      title: snapshot['title'] as String,
      description: snapshot['description'] as String,
      tags: List<String>.unmodifiable(
        (snapshot['tags'] as List).cast<String>(),
      ),
      artistNickname: json['artistNickname'] as String?,
      artistProfileAvailable: json['artistProfileAvailable'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      readAt: json['readAt'] == null
          ? null
          : DateTime.parse(json['readAt'] as String),
      liked: json['liked'] as bool,
    );
  }

  ReceivedArtwork withReadAt(DateTime value) => ReceivedArtwork(
    title: title,
    submissionId: submissionId,
    artistId: artistId,
    sourceIdeaId: sourceIdeaId,
    readAt: readAt ?? value,
    description: description,
    tags: tags,
    artistNickname: artistNickname,
    artistProfileAvailable: artistProfileAvailable,
    createdAt: createdAt,
    expiresAt: expiresAt,
    liked: liked,
  );

  ReceivedArtwork withLiked() => ReceivedArtwork(
    title: title,
    submissionId: submissionId,
    artistId: artistId,
    sourceIdeaId: sourceIdeaId,
    readAt: readAt,
    description: description,
    tags: tags,
    artistNickname: artistNickname,
    artistProfileAvailable: artistProfileAvailable,
    createdAt: createdAt,
    expiresAt: expiresAt,
    liked: true,
  );

  final String? submissionId;
  final String? artistId;
  final String? sourceIdeaId;
  final DateTime? readAt;
  // These fields describe the source idea snapshot, not a separate artwork title.
  final String title;
  final String? description;
  final List<String> tags;
  final String? artistNickname;
  final bool artistProfileAvailable;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool? liked;
}
