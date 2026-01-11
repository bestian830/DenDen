import 'dart:convert';

/// NostrPost model representing a Kind 1 text note
/// Supports threaded discussions (NIP-10)
class NostrPost {
  final int kind;
  final String sender;
  final String content;
  final DateTime time;
  final String eventId;
  
  // NIP-10 thread references
  final String? rootId;     // Root post ID (for reply chain)
  final String? replyToId;  // Direct parent ID (immediate reply target)
  final List<List<String>> tags; // All tags
  
  // Tree structure for comments
  List<NostrPost> children = [];

  NostrPost({
    required this.kind,
    required this.sender,
    required this.content,
    required this.time,
    required this.eventId,
    this.rootId,
    this.replyToId,
    this.tags = const [],
  });

  /// Check if this post is a reply (has parent)
  bool get isReply => rootId != null || replyToId != null;

  /// Create from home feed JSON (kind 1 from Go processEvent)
  factory NostrPost.fromJson(Map<String, dynamic> json) {
    return NostrPost(
      kind: json['kind'] as int,
      sender: (json['sender'] ?? json['pubkey']) as String,
      content: json['content'] as String,
      time: DateTime.parse(json['time'] as String),
      eventId: json['eventId'] as String? ?? '',
    );
  }

  /// Create from thread event JSON (from GetPostThread)
  factory NostrPost.fromThreadEvent(Map<String, dynamic> json) {
    // Parse tags
    List<List<String>> tags = [];
    if (json['tags'] != null) {
      tags = (json['tags'] as List).map((tag) => 
        (tag as List).map((e) => e.toString()).toList()
      ).toList();
    }
    
    return NostrPost(
      kind: 1,
      sender: json['sender'] as String? ?? '',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      eventId: json['eventId'] as String? ?? '',
      rootId: json['rootId'] as String?,
      replyToId: json['replyToId'] as String?,
      tags: tags,
    );
  }

  /// Copy with children
  NostrPost copyWithChildren(List<NostrPost> newChildren) {
    final copy = NostrPost(
      kind: kind,
      sender: sender,
      content: content,
      time: time,
      eventId: eventId,
      rootId: rootId,
      replyToId: replyToId,
      tags: tags,
    );
    copy.children = newChildren;
    return copy;
  }
}

/// Build a comment tree from flat list of posts
/// Input: Flat list from GetPostThread (all comments for a root)
/// Output: Tree structure where each comment has children
List<NostrPost> buildCommentTree(List<NostrPost> flatPosts, String rootId) {
  // Map for quick lookup: eventId -> post
  final Map<String, NostrPost> postMap = {};
  for (final post in flatPosts) {
    postMap[post.eventId] = post;
  }

  // Direct replies to root (top-level comments)
  final List<NostrPost> topLevel = [];

  // Build tree by assigning children
  for (final post in flatPosts) {
    final parentId = post.replyToId ?? post.rootId;
    
    if (parentId == rootId) {
      // Direct reply to root -> top level
      topLevel.add(post);
    } else if (parentId != null && postMap.containsKey(parentId)) {
      // Reply to another comment
      postMap[parentId]!.children.add(post);
    } else {
      // Orphan (parent not in list) -> treat as top level
      topLevel.add(post);
    }
  }

  // Sort by time (newest first or oldest first)
  topLevel.sort((a, b) => a.time.compareTo(b.time));
  
  // Recursively sort children
  void sortChildren(NostrPost post) {
    post.children.sort((a, b) => a.time.compareTo(b.time));
    for (final child in post.children) {
      sortChildren(child);
    }
  }
  for (final post in topLevel) {
    sortChildren(post);
  }

  return topLevel;
}

/// Parse thread events JSON from Go
List<NostrPost> parseThreadEvents(String json) {
  if (json.isEmpty || json == '[]') return [];
  
  try {
    final List<dynamic> list = jsonDecode(json);
    return list.map((e) => NostrPost.fromThreadEvent(e as Map<String, dynamic>)).toList();
  } catch (e) {
    return [];
  }
}
