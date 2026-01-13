import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../ffi/bridge.dart';
import '../models/nostr_post.dart';
import '../widgets/post_item.dart';
import '../utils/global_cache.dart'; // Centralized cache
import 'thread_screen.dart'; // Thread detail screen

/// HomeFeed - displays the main post feed with pull-to-refresh
class HomeFeed extends StatefulWidget {
  final ScrollController scrollController;
  final String myPubkey;
  const HomeFeed({super.key, required this.scrollController, required this.myPubkey});

  @override
  State<HomeFeed> createState() => HomeFeedState();
}

class HomeFeedState extends State<HomeFeed> {
  final List<NostrPost> _posts = [];
  final List<NostrPost> _incomingQueue = [];
  final Set<String> _requestedProfiles = {};
  StreamSubscription<String>? _subscription;
  bool _isLoading = true;
  
  // New Posts pill auto-hide
  bool _showNewPostsPill = false;
  Timer? _pillTimer;

  @override
  void initState() {
    super.initState();
    _subscribeToMessages();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// Insert user's own post at top of feed
  void insertMyPost(String content, String pubkey) {
    final newPost = NostrPost(
      kind: 1,
      sender: pubkey,
      content: content,
      time: DateTime.now(),
      eventId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
    );
    setState(() {
      _posts.insert(0, newPost);
    });
  }

  void _subscribeToMessages() {
    _subscription = DenDenBridge().messages.listen((jsonString) {
      if (!mounted) return;
      try {
        final data = json.decode(jsonString);
        final int kind = data['kind'] as int;

        // Kind 0: Metadata - update profile cache
        if (kind == 0) {
          final content = json.decode(data['content'] as String);
          final pubkey = (data['pubkey'] ?? data['sender']) as String?;
          if (pubkey != null) {
            globalProfileCache[pubkey] = {
              'name': content['name'] as String? ?? pubkey.substring(0, 8),
              'picture': content['picture'] as String? ?? '',
            };
            if (mounted) setState(() {}); // Rebuild UI with new profile
          }
        }

        // Kind 1 or 6: Text note / Repost
        if (kind == 1 || kind == 6) {
          final post = NostrPost.fromJson(data);

          // 自动请求未知的 profile (reposter or author)
          if (!globalProfileCache.containsKey(post.sender) && !_requestedProfiles.contains(post.sender)) {
            _requestedProfiles.add(post.sender);
            DenDenBridge().fetchProfile(post.sender);
          }
          
          // 如果是转发，也要请求原作者的 profile
          if (post.isRepost && post.originalPost != null) {
            final origSender = post.originalPost!.sender;
            if (!globalProfileCache.containsKey(origSender) && !_requestedProfiles.contains(origSender)) {
               _requestedProfiles.add(origSender);
               DenDenBridge().fetchProfile(origSender);
            }
          }

          if (_posts.length < 10) {
            // Initial load: add directly
            if (!_posts.any((p) => p.eventId == post.eventId)) {
              setState(() => _posts.add(post));
              _posts.sort((a, b) => b.time.compareTo(a.time));
            }
          } else {
            // After initial load: queue for "Show New Posts" banner
            if (!_posts.any((p) => p.eventId == post.eventId) &&
                !_incomingQueue.any((p) => p.eventId == post.eventId)) {
              _incomingQueue.insert(0, post);
              // Show pill with auto-hide
              _showPillWithTimer();
            }
          }
        }
      } catch (e) {
        debugPrint('Message parse error: $e');
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pillTimer?.cancel();
    super.dispose();
  }

  /// Show new posts pill and auto-hide after 4 seconds
  void _showPillWithTimer() {
    _pillTimer?.cancel();
    setState(() => _showNewPostsPill = true);
    _pillTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showNewPostsPill = false);
    });
  }

  Future<void> _handleRefresh() async {
    if (_incomingQueue.isNotEmpty) {
      setState(() {
        _posts.insertAll(0, _incomingQueue);
        _incomingQueue.clear();
        _showNewPostsPill = false; // Hide pill after tap
      });
      _pillTimer?.cancel();
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _handleRefresh,
          color: Colors.black,
          child: ListView.builder(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _posts.length,
            itemBuilder: (context, index) {
              final post = _posts[index];
              return PostItem(
                post: post,
                myPubkey: widget.myPubkey,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ThreadScreen(
                      rootPost: post,
                      myPubkey: widget.myPubkey,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // "Show N New Posts" banner (auto-hides after 4s)
        if (_showNewPostsPill && _incomingQueue.isNotEmpty)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  _handleRefresh();
                  widget.scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Show ${_incomingQueue.length} New Posts',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
