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

  /// Stream of incoming Nostr messages
  /// Messages are JSON strings with "kind", "sender", "content", "time", "eventId",
  /// "authorName", and "avatarUrl" fields
  Stream<String> get messages {
    return _eventChannel.receiveBroadcastStream().cast<String>();
  }
}
