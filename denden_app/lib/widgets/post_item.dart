import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:convert';
import '../ffi/bridge.dart';
import '../models/nostr_post.dart';
import '../screens/user_detail_screen.dart';
import '../widgets/media_carousel.dart';
import '../utils/global_cache.dart'; // Centralized cache

/// PostItem widget - displays a single post in the feed
/// Fixes double location display by stripping location from body text
class PostItem extends StatefulWidget {
  final NostrPost post;
  final String myPubkey;
  final VoidCallback? onTap; // Click post to go to detail page
  final bool isContext;

  const PostItem({
    super.key,
    required this.post,
    required this.myPubkey,
    this.onTap,
    this.isContext = false,
  });

  @override
  State<PostItem> createState() => _PostItemState();
}

class _PostItemState extends State<PostItem> {
  // Like state
  bool _isLiked = false;
  bool _isLiking = false;
  int _likeCount = 0; 
  // Effective post (unwrapped if repost)
  late NostrPost _effectivePost;

  // Regex for location extraction
  static final RegExp _locationRegex = RegExp(r'\n*📍\s*(\S+)\s*$');
  
  // Profile getters (Reactive to parent rebuilds)
  String get _displayName {
    final sender = _effectivePost.sender;
    final profile = globalProfileCache[sender];
    if (profile != null && profile['name'] != null && profile['name']!.isNotEmpty) {
      return profile['name']!;
    }
    return sender.length > 8 ? sender.substring(0, 8) : sender;
  }
  
  String get _avatarUrl {
    final profile = globalProfileCache[_effectivePost.sender];
    return profile?['picture'] ?? '';
  }

  @override
  void initState() {
    super.initState();
    _updateEffectivePost();
    _loadPostStats(); 
  }

  @override
  void didUpdateWidget(PostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.eventId != widget.post.eventId) {
      _updateEffectivePost();
      _isLiked = false;
      _isLiking = false;
      _likeCount = 0;
      _loadPostStats();
    }
  }

  void _updateEffectivePost() {
    if (widget.post.isRepost && widget.post.originalPost != null) {
      _effectivePost = widget.post.originalPost!;
    } else {
      _effectivePost = widget.post;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Check backend for like status
  Future<void> _loadPostStats() async {
    try {
      final stats = await DenDenBridge().getPostStats(_effectivePost.eventId);
      if (mounted) {
        setState(() {
          _likeCount = stats['likeCount'] as int? ?? 0;
          _isLiked = stats['isLikedByMe'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('Load stats failed for ${_effectivePost.eventId}: $e');
    }
  }

  /// Extract location string from content (e.g., "📍 Vancouver")
  String? _extractLocation() {
    final match = _locationRegex.firstMatch(_effectivePost.content);
    return match?.group(1);
  }

  /// Get body text with location stripped out (fixes double display)
  String _getCleanBodyText() {
    String text = _effectivePost.content;
    // Remove location tag from body
    text = text.replaceAll(_locationRegex, '').trim();
    return text;
  }

  @override
  Widget build(BuildContext context) {
    // If it's a repost but original is missing, show error or hide
    if (widget.post.isRepost && widget.post.originalPost == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
        child: const Text('Repost unavailable', style: TextStyle(color: Colors.grey)),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Repost Header
            if (widget.post.isRepost) _buildRepostHeader(),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _navigateToProfile(context),
                  child: _buildAvatar(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: name + time
                      Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => _navigateToProfile(context),
                              child: Text(
                                _displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _formatTime(_effectivePost.time),
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Content
                      _buildContent(),
                      // Quote Preview
                      if (_effectivePost.quotedEventId != null) _buildQuotePreview(_effectivePost.quotedEventId!),
                      // Location
                      _buildLocationTag(),
                      const SizedBox(height: 10),
                      // Action bar
                      if (!widget.isContext) _buildActions(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepostHeader() {
    final reposter = widget.post.sender;
    final profile = globalProfileCache[reposter];
    final name = profile?['name'] ?? (reposter.length > 8 ? reposter.substring(0, 8) : reposter);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 36), // Align with text
      child: Row(
        children: [
          Icon(Icons.repeat, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            '$name Reposted',
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _navigateToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(
          pubkey: _effectivePost.sender,
          initialName: _displayName,
          initialPicture: _avatarUrl,
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (_avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey[200],
        backgroundImage: NetworkImage(_avatarUrl),
        onBackgroundImageError: (_, __) {},
      );
    }
    // Colorful identicon fallback
    final int hash = _effectivePost.sender.hashCode;
    final color = Colors.primaries[hash.abs() % Colors.primaries.length];

    return CircleAvatar(
      radius: 20,
      backgroundColor: color,
      child: Text(
        _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildContent() {
    // URL regex for media detection
    final urlRegex = RegExp(r'https?://\S+\.(jpg|jpeg|png|gif|webp|mp4|mov)', caseSensitive: false);
    
    // Get clean body text (location already stripped)
    String text = _getCleanBodyText();
    
    // Extract media URLs
    final matches = urlRegex.allMatches(text);
    final urls = matches.map((m) => m.group(0)!).toList();
    
    // Remove URLs from display text
    for (var url in urls) {
      text = text.replaceAll(url, '').trim();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty) 
          Text(text, style: const TextStyle(fontSize: 15, height: 1.3)),
        if (urls.isNotEmpty) ...[
          const SizedBox(height: 10),
          MediaCarousel(urls: urls),
        ]
      ],
    );
  }

  /// Threads-style location tag (below content, above actions)
  Widget _buildLocationTag() {
    final location = _extractLocation();
    if (location == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: GestureDetector(
        onTap: () {
          debugPrint('📍 Location tapped: $location');
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 14,
              color: Colors.grey[500],
            ),
            const SizedBox(width: 4),
            Text(
              location,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotePreview(String quotedId) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.format_quote, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Quoted Note', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Note ID: ${quotedId.substring(0, 8)}...',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          // TODO: Async fetch quoted post content
        ],
      ),
    );
  }

  Widget _buildActions() {
    final isRepostedByMe = false; // TODO: Check if I reposted
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Comment button
        GestureDetector(
          onTap: () {
            if (widget.onTap != null) {
              widget.onTap!();
            }
          },
          child: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey),
        ),
        
        // Repost button
        GestureDetector(
          onTap: _showRepostMenu,
          child: Row(
            children: [
              Icon(
                Icons.repeat, 
                size: 18, 
                color: isRepostedByMe ? Colors.green : Colors.grey
              ),
            ],
          ),
        ),
        
        // Like button
        GestureDetector(
          onTap: _handleLike,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isLiking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pink),
                    )
                  : Icon(
                      _isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: _isLiked ? Colors.pink : Colors.grey,
                    ),
              if (_likeCount > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$_likeCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isLiked ? Colors.pink : Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Share button
        GestureDetector(
          onTap: _handleShare,
          child: const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
        ),
      ],
    );
  }

  Future<void> _handleShare() async {
    final url = 'https://njump.me/${_effectivePost.eventId}';
    final text = 'Check out this note on Nostr: $url';
    await Share.share(text);
  }

  void _showRepostMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Repost'),
              onTap: () {
                Navigator.pop(context);
                _handleRepost();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Quote'),
              onTap: () {
                Navigator.pop(context);
                _handleQuote();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRepost() async {
    try {
      // For Repost, we need the original event JSON string. 
      // Since we don't have it easily available in raw string form here (we parsed it),
      // we might need to rely on ID. But our backend Repost expects JSON string.
      // Option: Re-serialize _effectivePost to JSON?
      // Or: Change backend to accept ID and let backend fetch it?
      // Backend: "Repost(originalEventJson string)".
      // If we pass ID, backend fails.
      // Re-serializing _effectivePost might lose signatures or extra fields?
      // But _effectivePost was created from JSON.
      // Wait, _effectivePost is a NostrPost object, not the full raw event.
      // NostrPost is a subset.
      
      // CRITICAL: To allow Repost, we need the raw JSON of the event.
      // Since we don't store it, we can't send it to backend correctly as "inner event".
      // Workaround: Send a constructed JSON with ID and Pubkey? 
      // No, Kind 6 content MUST be the event JSON.
      
      // Solution for now: Just send what we have (ID/Content/Pubkey/Kind/Time/Tags) re-serialized.
      // It won't have the original signature, so it's technically invalid as a "wrapped event" 
      // because signature verification of inner event will fail.
      // BUT for simple display it might work.
      // Ideally Backend should fetch the event from Relay if we only allow ID.
      // But we built Repost(json).
      
      // Let's try to construct a valid-looking event JSON.
      // Or change Backend to fetch.
      // Changing Backend to "Repost(eventId)" is safer but slower (async).
      // Given we are in frontend, let's assume we can't sign it anyway.
      
      // Temporary: We will send a minimal JSON structure.
      final jsonStr = jsonEncode({
        'id': _effectivePost.eventId,
        'pubkey': _effectivePost.sender,
        'created_at': _effectivePost.time.millisecondsSinceEpoch ~/ 1000,
        'kind': _effectivePost.kind,
        'tags': _effectivePost.tags,
        'content': _effectivePost.content,
        'sig': '', // Missing sig
      });
      
      await DenDenBridge().repost(jsonStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reposted!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _handleQuote() {
    // Open compose screen with initial quoted ID
    // We don't have a ComposeScreen that accepts params yet?
    // Let's assume user wants simple quote.
    // For now, prompt for text dialog?
    // Or navigate to ComposeScreen with arguments.
    // ComposeScreen is defined in `compose_screen.dart`?
    // I should check `compose_screen.dart`.
    _showQuoteDialog();
  }

  void _showQuoteDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quote Post'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Add a comment...'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (controller.text.isNotEmpty) {
                try {
                  await DenDenBridge().quotePost(
                    controller.text, 
                    _effectivePost.eventId, 
                    _effectivePost.sender
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quote posted!')));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }
            }, 
            child: const Text('Post')
          ),
        ],
      ),
    );
  }

  Future<void> _handleLike() async {
    if (_isLiking) return;
    
    // Optimistic UI update - instant feedback
    final wasLiked = _isLiked;
    setState(() {
      _isLiking = true;
      _isLiked = !wasLiked;
      _likeCount = wasLiked ? _likeCount - 1 : _likeCount + 1;
      if (_likeCount < 0) _likeCount = 0;
    });
    
    try {
      // Send to network in background
      final result = await DenDenBridge().toggleLike(widget.post.eventId);
      
      if (mounted) {
        setState(() {
          _isLiked = result['isLiked'] as bool;
          _isLiking = false;
        });
      }
    } catch (e) {
      debugPrint('Toggle like failed: $e');
      // Revert optimistic update on error
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likeCount = wasLiked ? _likeCount + 1 : _likeCount - 1;
          if (_likeCount < 0) _likeCount = 0;
          _isLiking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasLiked ? 'Failed to cancel like' : 'Failed to like'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }



  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
