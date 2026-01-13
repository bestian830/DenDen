import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class DenDenBridge {
  // Define the MethodChannel for method calls
  static const MethodChannel _methodChannel = MethodChannel('com.denden.mobile/bridge');
  
  // Define the EventChannel for streaming messages
  static const EventChannel _eventChannel = EventChannel('com.denden.mobile/events');

  // Singleton pattern
  static final DenDenBridge _instance = DenDenBridge._internal();
  factory DenDenBridge() => _instance;
  DenDenBridge._internal();

  /// Initialize the Go client
  /// This must be called before any other method
  Future<void> initialize() async {
    try {
      await _methodChannel.invokeMethod('Initialize');
    } on PlatformException catch (e) {
      throw Exception('Failed to initialize: ${e.message}');
    }
  }

  /// Get user's identity as JSON string
  /// Returns JSON with npub, nsec, publicKey, privateKey
  Future<String> getIdentity() async {
    try {
      final String result = await _methodChannel.invokeMethod('GetIdentity');
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get identity: ${e.message}');
    }
  }

  /// Connect to default Nostr relays and start listening
  /// Automatically connects to seed relays and begins receiving messages
  Future<void> connectToDefault() async {
    try {
      await _methodChannel.invokeMethod('ConnectToDefault');
    } on PlatformException catch (e) {
      throw Exception('Failed to connect: ${e.message}');
    }
  }

  /// Publish a short text note (Kind 1) to the network
  /// Optionally include tags (e.g., location ['g', 'geohash', 'City'])
  Future<void> publishTextNote(String content, {List<List<String>>? tags}) async {
    try {
      final Map<String, dynamic> args = {'content': content};
      
      // Add tags if provided
      if (tags != null && tags.isNotEmpty) {
        args['tags'] = tags;
        debugPrint('🚀 Sending Event with tags: $tags');
      }
      
      await _methodChannel.invokeMethod('PublishTextNote', args);
    } on PlatformException catch (e) {
      throw Exception('Failed to publish note: ${e.message}');
    }
  }

  /// Publish user metadata (Kind 0) to the network
  /// Updates the user's name, about, avatar, banner, and website
  Future<void> publishMetadata(String name, String about, String picture, {String banner = '', String website = ''}) async {
    try {
      // Serialize all fields into a single JSON string
      final metadataJson = jsonEncode({
        'name': name,
        'about': about,
        'picture': picture,
        'banner': banner,
        'website': website,
      });
      await _methodChannel.invokeMethod('PublishMetadata', {
        'metadataJson': metadataJson,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to publish metadata: ${e.message}');
    }
  }

  /// Get a user's profile (name, avatar, etc.) by public key
  /// Returns JSON with profile data if cached, or cached:false if not available
  /// 
  /// Example response:
  /// ```json
  /// {
  ///   "pubkey": "abc123...",
  ///   "cached": true,
  ///   "name": "Alice",
  ///   "picture": "https://...",
  ///   "about": "Bitcoin enthusiast"
  /// }
  /// ```
  Future<String> getProfile(String pubkey) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetProfile', {'pubkey': pubkey});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get profile: ${e.message}');
    }
  }

  /// Repost (Kind 6)
  /// Returns the new event ID
  Future<String> repost(String originalEventJson) async {
    try {
      final String result = await _methodChannel.invokeMethod('Repost', {'originalEventJson': originalEventJson});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to repost: ${e.message}');
    }
  }

  /// Quote Post (Kind 1 with tags)
  /// Returns the new event ID
  Future<String> quotePost(String content, String quotedEventId, String authorPubkey) async {
    try {
      final String result = await _methodChannel.invokeMethod('QuotePost', {
        'content': content,
        'quotedEventId': quotedEventId,
        'authorPubkey': authorPubkey,
      });
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to quote post: ${e.message}');
    }
  }



  /// Actively fetch profile metadata from relay
  Future<void> fetchProfile(String pubkey) async {
    try {
      await _methodChannel.invokeMethod('fetchProfile', {'pubkey': pubkey});
    } on PlatformException catch (e) {
      throw Exception('Failed to fetch profile: ${e.message}');
    }
  }

  /// Toggle like state for a post
  /// Returns a map with {isLiked: bool, likeEventId: String, postId: String}
  /// Go manages the like state internally - Flutter doesn't need to track IDs
  Future<Map<String, dynamic>> toggleLike(String postId) async {
    try {
      final result = await _methodChannel.invokeMethod('ToggleLike', {'postId': postId});
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to toggle like: ${e.message}');
    }
  }

  /// Check if a post is currently liked (from Go cache)
  Future<bool> isPostLiked(String postId) async {
    try {
      final bool result = await _methodChannel.invokeMethod('IsPostLiked', {'postId': postId});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to check like status: ${e.message}');
    }
  }

  /// Deprecated: Use toggleLike instead
  Future<void> likePost(String eventId) async {
    await toggleLike(eventId);
  }

  /// Get post statistics (like count, reply count, etc.) from relay
  /// Returns map with {postId, likeCount, replyCount, isLikedByMe}
  /// Note: Uses async relay query with 3s timeout
  Future<Map<String, dynamic>> getPostStats(String postId) async {
    try {
      final result = await _methodChannel.invokeMethod('GetPostStats', {'postId': postId});
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to get post stats: ${e.message}');
    }
  }

  /// Reply to a post (sends Nostr Kind 1 with 'e' tag)
  Future<void> replyPost(String eventId, String content) async {
    try {
      await _methodChannel.invokeMethod('ReplyPost', {
        'eventId': eventId,
        'content': content,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to reply to post: ${e.message}');
    }
  }

  /// Get all comments under a root post (threaded discussion)
  /// Returns map with {rootId, count, events: JSON string}
  Future<Map<String, dynamic>> getPostThread(String rootEventId) async {
    try {
      final result = await _methodChannel.invokeMethod('GetPostThread', {'rootEventId': rootEventId});
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to get post thread: ${e.message}');
    }
  }

  /// Get notifications (mentions/replies to current user)
  /// Returns JSON string of ThreadEvent array
  Future<String> getNotifications({int limit = 20}) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetNotifications', {'limit': limit});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get notifications: ${e.message}');
    }
  }

  /// Get user activity feed (posts (Kind 1) and reposts (Kind 6))
  /// Returns JSON string of array of NostrPost-compatible maps
  Future<String> getUserFeed(String pubkey, {int limit = 20}) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetUserFeed', {'pubkey': pubkey, 'limit': limit});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get user feed: ${e.message}');
    }
  }

  /// Get user posts (Kind 1 excluding replies + Kind 6)
  Future<String> getUserPosts(String pubkey, {int limit = 20}) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetUserPosts', {'pubkey': pubkey, 'limit': limit});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get user posts: ${e.message}');
    }
  }

  /// Get user replies (Kind 1 replies only)
  /// Overrides the legacy method name, but returns enrich NostrPost list
  Future<String> getUserRepliesWithProfile(String pubkey, {int limit = 20}) async {
     try {
       // We use the new backend method GetUserReplies which returns enriched events
       final String result = await _methodChannel.invokeMethod('GetUserReplies', {'pubkey': pubkey, 'limit': limit});
       return result;
     } on PlatformException catch (e) {
       throw Exception('Failed to get user replies: ${e.message}');
     }
  }

  /// Get user media (Kind 1 with media)
  Future<String> getUserMedia(String pubkey, {int limit = 20}) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetUserMedia', {'pubkey': pubkey, 'limit': limit});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get user media: ${e.message}');
    }
  }

  /// Get user highlights (Kind 9802)
  Future<String> getUserHighlights(String pubkey, {int limit = 20}) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetUserHighlights', {'pubkey': pubkey, 'limit': limit});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get user highlights: ${e.message}');
    }
  }

  /// Get user reposts (Kind 6)
  Future<String> getUserReposts(String pubkey, {int limit = 20}) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetUserReposts', {'pubkey': pubkey, 'limit': limit});
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to get user reposts: ${e.message}');
    }
  }

  /// Get single event by ID
  Future<String> getSingleEvent(String eventId) async {
    try {
      final String result = await _methodChannel.invokeMethod('GetSingleEvent', {'eventId': eventId});
      return result;
    } on PlatformException catch (e) {
       throw Exception('Failed to get event: ${e.message}');
    }
  }

  // --- Social Graph (Kind 3) ---

  /// Get list of pubkeys that [pubkey] follows
  Future<List<String>> getFollowing(String pubkey) async {
    try {
      final String jsonStr = await _methodChannel.invokeMethod('GetFollowing', {'pubkey': pubkey});
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.cast<String>();
    } on PlatformException catch (e) {
      debugPrint('Failed to get following: ${e.message}');
      return [];
    }
  }

  /// Get list of pubkeys that follow [pubkey] (Reverse lookup)
  Future<List<String>> getFollowers(String pubkey) async {
    try {
      final String jsonStr = await _methodChannel.invokeMethod('GetFollowers', {'pubkey': pubkey});
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.cast<String>();
    } on PlatformException catch (e) {
      debugPrint('Failed to get followers: ${e.message}');
      return [];
    }
  }

  /// Follow a user (Update Kind 3)
  Future<void> follow(String pubkeyToFollow) async {
    try {
      await _methodChannel.invokeMethod('Follow', {'pubkey': pubkeyToFollow});
    } on PlatformException catch (e) {
      throw Exception('Failed to follow: ${e.message}');
    }
  }

  /// Unfollow a user (Update Kind 3)
  Future<void> unfollow(String pubkeyToUnfollow) async {
    try {
      await _methodChannel.invokeMethod('Unfollow', {'pubkey': pubkeyToUnfollow});
    } on PlatformException catch (e) {
      throw Exception('Failed to unfollow: ${e.message}');
    }
  }

  Future<bool> sendDirectMessage(String receiver, String content) async {
    try {
      final bool result = await _methodChannel.invokeMethod('SendDirectMessage', {'receiver': receiver, 'content': content});
      return result;
    } on PlatformException catch (e) {
      print("Failed to send DM: '${e.message}'.");
      return false;
    }
  }

  Future<void> fetchMessages(int limit) async {
    try {
      final String? logs = await _methodChannel.invokeMethod('FetchMessages', {'limit': limit});
      if (logs != null) {
        debugPrint("========== NATIVE LOGS START ==========");
        debugPrint(logs);
        debugPrint("=========== NATIVE LOGS END ===========");
      }
    } on PlatformException catch (e) {
      print("Failed to fetch messages: '${e.message}'.");
    }
  }

  Future<String> getConversations() async {
    try {
      final Uint8List? data = await _methodChannel.invokeMethod('GetConversations');
      if (data == null) return "[]";
      return utf8.decode(data);
    } catch (e) {
      print("Failed to get conversations: '$e'.");
      return "[]";
    }
  }

  Future<String> getChatMessages(String partner) async {
    try {
      final Uint8List? data = await _methodChannel.invokeMethod('GetChatMessages', {'partner': partner});
      if (data == null) return "[]";
      return utf8.decode(data);
    } catch (e) {
      print("Failed to get chat messages: '$e'.");
      return "[]";
    }
  }

  /// Stream of incoming Nostr messages
  /// Messages are JSON strings with "kind", "sender", "content", "time", "eventId",
  /// "authorName", and "avatarUrl" fields
  Stream<String> get messages {
    return _eventChannel.receiveBroadcastStream().cast<String>();
  }
}
