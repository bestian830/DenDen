import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/nostr_post.dart';
import '../ffi/bridge.dart';
import 'post_item.dart';
import '../screens/thread_screen.dart';

class ReplyThreadItem extends StatelessWidget {
  final NostrPost replyPost;
  final String myPubkey;
  final VoidCallback? onTap;

  const ReplyThreadItem({
    super.key,
    required this.replyPost,
    required this.myPubkey,
    this.onTap,
  });

  Future<NostrPost?> _fetchParent() async {
    // Determine parent ID specifically (NIP-10)
    // We want the immediate parent to show context
    // Ideally we parse tags properly. For MVP, use the last 'e' tag as reply-to
    String? replyToId = replyPost.replyToId;
    if (replyToId != null && replyToId.isNotEmpty) {
      try {
        final jsonStr = await DenDenBridge().getSingleEvent(replyToId);
        final List<dynamic> list = jsonDecode(jsonStr);
        if (list.isNotEmpty) {
           return NostrPost.fromJson(list[0]);
        }
      } catch (e) {
        // Parent not found or error
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NostrPost?>(
      future: _fetchParent(),
      builder: (context, snapshot) {
        final parentPost = snapshot.data;
        
        // If no parent found, just show the reply itself (fallback) or nothing?
        // Twitter shows "Replying to @user" if parent is missing.
        // But if we have it, we show it detailed.
        
        return Column(
          children: [
            if (parentPost != null) ...[
              // Parent Post (Reduced or Full?)
              // Twitter shows it fully but maybe without actions to keep it clean, 
              // connected by a line.
              // Let's wrap PostItem to custom paint line.
              Stack(
                children: [
                   // The Line
                   Positioned(
                     left: 36, // Center of avatar roughly (avatar is 40? radius 20?)
                     // PostItem avatar is CircleAvatar, usually radius 20? 
                     // Need to check PostItem dimensions.
                     // Assuming standard layout padding.
                     // Let's assume standard avatar left padding.
                     top: 50, 
                     bottom: 0,
                     child: Container(
                       width: 2,
                       color: Colors.grey[300],
                     ),
                   ),
                   PostItem(
                     post: parentPost,
                     myPubkey: myPubkey,
                     isContext: true, // Add this flag to PostItem to hide actions if needed or small avatar
                     onTap: () {
                         Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ThreadScreen(
                              rootPost: parentPost, 
                              myPubkey: myPubkey
                            ),
                          ),
                        );
                     },
                   ),
                ],
              ),
            ],
            
            // The Reply itself
            PostItem(
              post: replyPost,
              myPubkey: myPubkey,
              onTap: onTap,
            ),
          ],
        );
      },
    );
  }
}
