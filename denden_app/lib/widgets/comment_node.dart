import 'package:flutter/material.dart';
import 'package:denden_app/models/nostr_post.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'package:denden_app/utils/global_cache.dart';

/// Recursive comment node widget for threaded discussions
class CommentNode extends StatefulWidget {
  final NostrPost comment;
  final int depth;
  final Function(NostrPost)? onReplyItem;
  final VoidCallback? onTap;
  final String myPubkey;

  const CommentNode({
    super.key,
    required this.comment,
    required this.myPubkey,
    this.depth = 0,
    this.onReplyItem,
    this.onTap,
  });

  @override
  State<CommentNode> createState() => _CommentNodeState();
}

class _CommentNodeState extends State<CommentNode> {
  bool _isLiked = false;
  bool _isLiking = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await DenDenBridge().getPostStats(widget.comment.eventId);
      if (mounted) {
        setState(() {
          _likeCount = stats['likeCount'] as int? ?? 0;
          _isLiked = stats['isLikedByMe'] as bool? ?? false;
        });
      }
    } catch (e) {
      debugPrint('Load comment stats failed: $e');
    }
  }

  Future<void> _handleLike() async {
    if (_isLiking) return;

    final wasLiked = _isLiked;
    setState(() {
      _isLiking = true;
      _isLiked = !wasLiked;
      _likeCount = wasLiked ? _likeCount - 1 : _likeCount + 1;
      if (_likeCount < 0) _likeCount = 0;
    });

    try {
      final result = await DenDenBridge().toggleLike(widget.comment.eventId);
      if (mounted) {
        setState(() {
          _isLiked = result['isLiked'] as bool;
          _isLiking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likeCount = wasLiked ? _likeCount + 1 : _likeCount - 1;
          if (_likeCount < 0) _likeCount = 0;
          _isLiking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommentRow(context),
        if (widget.comment.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Column(
              children: widget.comment.children.map((child) {
                return CommentNode(
                  comment: child,
                  myPubkey: widget.myPubkey,
                  depth: widget.depth + 1,
                  onReplyItem: widget.onReplyItem,
                  onTap: widget.onTap,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildCommentRow(BuildContext context) {
    // Look up profile in global cache
    final profile = globalProfileCache[widget.comment.sender];
    final displayName = profile?['name'] ?? _shortenPubkey(widget.comment.sender);
    final avatarUrl = profile?['picture'];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.depth > 0)
            Container(
              width: 2,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          
          Expanded(
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildAvatar(displayName, avatarUrl),
                        const SizedBox(width: 8),
                        Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(widget.comment.time),
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.comment.content,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _handleLike,
                          child: Row(
                            children: [
                              _isLiking
                                  ? const SizedBox(
                                      width: 14, height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pink),
                                    )
                                  : Icon(
                                      _isLiked ? Icons.favorite : Icons.favorite_border,
                                      size: 14,
                                      color: _isLiked ? Colors.pink : Colors.grey,
                                    ),
                              if (_likeCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '$_likeCount',
                                  style: TextStyle(fontSize: 12, color: _isLiked ? Colors.pink : Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => widget.onReplyItem?.call(widget.comment),
                          child: Row(
                            children: [
                              Icon(Icons.reply, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'Reply',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String displayName, String? url) {
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: NetworkImage(url),
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: Colors.grey.shade200,
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _shortenPubkey(String pubkey) {
    if (pubkey.length > 8) return pubkey.substring(0, 8);
    return pubkey;
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${time.month}/${time.day}';
  }
}
