import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
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
  
  const PostItem({
    super.key,
    required this.post,
    required this.myPubkey,
    this.onTap,
  });

  @override
  State<PostItem> createState() => _PostItemState();
}

class _PostItemState extends State<PostItem> {
  String _displayName = '';
  String _avatarUrl = '';
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _isLiked = false;
  bool _isLiking = false;
  int _likeCount = 0; // Like count for optimistic updates

  // Regex for location extraction
  static final RegExp _locationRegex = RegExp(r'\n*📍\s*(\S+)\s*$');

  @override
  void initState() {
    super.initState();
    _displayName = widget.post.sender.length > 8 
        ? widget.post.sender.substring(0, 8) 
        : widget.post.sender;
    _loadProfile();
    _loadPostStats(); // Load like count from relay
  }

  @override
  void didUpdateWidget(PostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset state when the post changes (ListView recycling)
    if (oldWidget.post.eventId != widget.post.eventId) {
      _isLiked = false;
      _isLiking = false;
      _likeCount = 0;
      _displayName = widget.post.sender.length > 8 
          ? widget.post.sender.substring(0, 8) 
          : widget.post.sender;
      _avatarUrl = '';
      _retryCount = 0;
      _loadProfile();
      _loadPostStats();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _loadProfile() async {
    // 1. Is this me? Load from SharedPreferences
    if (widget.myPubkey.isNotEmpty && widget.post.sender == widget.myPubkey) {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _displayName = prefs.getString('profile_name') ?? _displayName;
          _avatarUrl = prefs.getString('profile_picture') ?? '';
        });
      }
      return;
    }

    // 2. Check global cache
    if (_checkCache()) return;

    // 3. Retry if not cached
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _retryCount >= 5) {
        timer.cancel();
        return;
      }
      _retryCount++;
      DenDenBridge().getProfile(widget.post.sender);
      if (_checkCache()) timer.cancel();
    });
  }

  bool _checkCache() {
    if (globalProfileCache.containsKey(widget.post.sender)) {
      final cached = globalProfileCache[widget.post.sender];
      if (cached != null && mounted) {
        setState(() {
          _displayName = cached['name'] ?? _displayName;
          _avatarUrl = cached['picture'] ?? '';
        });
        return true;
      }
    }
    return false;
  }

  /// Extract location string from content (e.g., "📍 Vancouver")
  String? _extractLocation() {
    final match = _locationRegex.firstMatch(widget.post.content);
    return match?.group(1);
  }

  /// Get body text with location stripped out (fixes double display)
  String _getCleanBodyText() {
    String text = widget.post.content;
    // Remove location tag from body
    text = text.replaceAll(_locationRegex, '').trim();
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
        child: Row(
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
                      _formatTime(widget.post.time),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Content (with location stripped)
                _buildContent(),
                // Location tag (Threads style)
                _buildLocationTag(),
                const SizedBox(height: 10),
                // Action bar
                _buildActions(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  void _navigateToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(
          pubkey: widget.post.sender,
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
    final int hash = widget.post.sender.hashCode;
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

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Comment button
        GestureDetector(
          onTap: () {
            if (widget.onTap != null) {
              widget.onTap!();
            } else {
              debugPrint('Reply to: ${widget.post.eventId}');
            }
          },
          child: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey),
        ),
        // Repost button (placeholder)
        const Icon(Icons.repeat, size: 18, color: Colors.grey),
        // Like button with count
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
        // Share button (placeholder)
        const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
      ],
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

  /// Load post stats from relay (like count, is liked by me)
  Future<void> _loadPostStats() async {
    try {
      final stats = await DenDenBridge().getPostStats(widget.post.eventId);
      if (mounted) {
        setState(() {
          _likeCount = stats['likeCount'] as int? ?? 0;
          _isLiked = stats['isLikedByMe'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('Load post stats failed: $e');
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
