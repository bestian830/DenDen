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

  // Repost & Quote fields
  final bool isRepost;
  final String? repostBy;
  final NostrPost? originalPost;
  final String? quotedEventId;

  NostrPost({
    required this.kind,
    required this.sender,
    required this.content,
    required this.time,
    required this.eventId,
    this.rootId,
    this.replyToId,
    this.tags = const [],
    this.isRepost = false,
    this.repostBy,
    this.originalPost,
    this.quotedEventId,
  });

  /// Check if this post is a reply (has parent)
  bool get isReply => rootId != null || replyToId != null;

  /// Create from home feed JSON (kind 1/6 from Go processEvent)
  factory NostrPost.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as int;
    final sender = (json['sender'] ?? json['pubkey']) as String;
    String content = json['content'] as String;
    
    // Parse tags if available
    List<List<String>> tags = [];
    if (json['tags'] != null) {
      if (json['tags'] is List) {
        tags = (json['tags'] as List).map((e) => List<String>.from(e)).toList();
      }
    }

    bool isRepost = kind == 6;
    NostrPost? originalPost;
    String? repostBy;
    String? quotedEventId;

    if (isRepost) {
      repostBy = sender;
      try {
        final innerJson = jsonDecode(content);
        originalPost = NostrPost.fromRawEvent(innerJson);
        content = ''; // Clear raw JSON from display
      } catch (e) {
        // Invalid repost content
      }
    } else {
      // Check for Quote (Kind 1 with 'q' tag)
      // Look for ["q", "event_id"]
      final qTag = tags.firstWhere(
        (t) => t.isNotEmpty && t[0] == 'q', 
        orElse: () => []
      );
      if (qTag.isNotEmpty && qTag.length > 1) {
        quotedEventId = qTag[1];
      }
    }

    return NostrPost(
      kind: kind,
      sender: sender,
      content: content,
      time: DateTime.parse(json['time'] as String),
      eventId: json['eventId'] as String? ?? '',
      tags: tags,
      isRepost: isRepost,
      repostBy: repostBy,
      originalPost: originalPost,
      quotedEventId: quotedEventId,
    );
  }

  /// Create from raw Nostr event JSON (e.g. inside a Repost)
  /// Keys: id, pubkey, created_at, kind, tags, content
  factory NostrPost.fromRawEvent(Map<String, dynamic> json) {
    // Parse time: created_at is unix timestamp (int)
    final createdAt = json['created_at'] is int 
        ? DateTime.fromMillisecondsSinceEpoch((json['created_at'] as int) * 1000)
        : DateTime.now();
        
    List<List<String>> tags = [];
    if (json['tags'] != null && json['tags'] is List) {
      tags = (json['tags'] as List).map((e) => List<String>.from(e)).toList();
    }

    // Check for quoted post inside this raw event? 
    // Yes, a reposted event could be a quote. 
    // But for simplicity, let's just parse basic fields first.
    // If originalPost is also a Quote, we support it naturally if UI supports recursion.
    // But let's keep it simple.

    return NostrPost(
      kind: json['kind'] as int? ?? 1,
      sender: json['pubkey'] as String? ?? '',
      content: json['content'] as String? ?? '',
      time: createdAt,
      eventId: json['id'] as String? ?? '',
      tags: tags,
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
    
    // Check for Quote
    String? quotedEventId;
    final qTag = tags.firstWhere(
      (t) => t.isNotEmpty && t[0] == 'q', 
      orElse: () => []
    );
    if (qTag.isNotEmpty && qTag.length > 1) {
      quotedEventId = qTag[1];
    }
    
    return NostrPost(
      kind: 1, // Usually threads are Kind 1
      sender: json['sender'] as String? ?? '',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      eventId: json['eventId'] as String? ?? '',
      rootId: json['rootId'] as String?,
      replyToId: json['replyToId'] as String?,
      tags: tags,
      quotedEventId: quotedEventId,
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
      isRepost: isRepost,
      repostBy: repostBy,
      originalPost: originalPost,
      quotedEventId: quotedEventId,
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
