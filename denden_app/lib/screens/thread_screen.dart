import 'package:flutter/material.dart';
import 'package:denden_app/models/nostr_post.dart';
import 'package:denden_app/widgets/comment_node.dart';
import 'package:denden_app/widgets/post_item.dart';
import 'package:denden_app/ffi/bridge.dart';

/// Thread screen showing a root post with all its comments
class ThreadScreen extends StatefulWidget {
  final NostrPost rootPost;
  final String myPubkey;

  const ThreadScreen({
    super.key,
    required this.rootPost,
    required this.myPubkey,
  });

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  List<NostrPost> _commentTree = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  String? _replyingToId; // Replying to post ID
  String? _replyingToName; // Replying to post name

  @override
  void initState() {
    super.initState();
    _loadThread();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await DenDenBridge().getPostThread(widget.rootPost.eventId);
      final eventsJson = result['events'] as String? ?? '[]';
      final flatPosts = parseThreadEvents(eventsJson);
      final tree = buildCommentTree(flatPosts, widget.rootPost.eventId);
      
      if (mounted) {
        setState(() {
          _commentTree = tree;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _startReply(NostrPost? targetPost) {
    setState(() {
      if (targetPost != null) {
        _replyingToId = targetPost.eventId;
        _replyingToName = targetPost.sender.length > 8 
            ? targetPost.sender.substring(0, 8)
            : targetPost.sender;
      } else {
        _replyingToId = widget.rootPost.eventId;
        _replyingToName = null;
      }
    });
    // Focus on the input field
    FocusScope.of(context).requestFocus(FocusNode());
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty || _isSending) return;

    final targetId = _replyingToId ?? widget.rootPost.eventId;

    setState(() => _isSending = true);

    try {
      await DenDenBridge().replyPost(targetId, content);
      _replyController.clear();
      setState(() {
        _isSending = false;
        _replyingToId = null;
        _replyingToName = null;
      });
      // Reload comments
      _loadThread();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reply: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Den Den'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Main content (scrollable)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadThread,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Root post
                    PostItem(
                      post: widget.rootPost,
                      myPubkey: widget.myPubkey,
                      onTap: null, // Already on this screen
                    ),
                    
                    // Divider
                    const Divider(height: 1),
                    
                    // Comments section
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildCommentsSection(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Reply input bar
          _buildReplyBar(),
        ],
      ),
    );
  }

  Widget _buildCommentsSection() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Text('Load failed', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadThread,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_commentTree.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No comments yet, come and post one!',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    // Comment list
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments (${_countAllComments()})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        ..._commentTree.map((comment) => CommentNode(
          comment: comment,
          myPubkey: widget.myPubkey,
          depth: 0,
          onReplyItem: _startReply,
          onTap: () {}, // TODO: expand/collapse
        )),
      ],
    );
  }

  int _countAllComments() {
    int count = 0;
    void countRecursive(List<NostrPost> posts) {
      for (final post in posts) {
        count++;
        countRecursive(post.children);
      }
    }
    countRecursive(_commentTree);
    return count;
  }

  Widget _buildReplyBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Replying to indicator
          if (_replyingToName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    'Replying to $_replyingToName',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      _replyingToId = null;
                      _replyingToName = null;
                    }),
                    child: Icon(Icons.close, size: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          
          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replyController,
                  decoration: InputDecoration(
                    hintText: _replyingToName != null ? 'Replying to $_replyingToName...' : 'Post a comment...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    isDense: true,
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendReply(),
                ),
              ),
              const SizedBox(width: 8),
              _isSending
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: _sendReply,
                      icon: Icon(Icons.send, color: Colors.blue.shade600),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
