import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'dart:convert';
import 'chat_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'notification_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => ChatListScreenState();
}

class ChatListScreenState extends State<ChatListScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }
  
  // Refresh when returning
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    debugPrint("[Flutter] ChatListScreen: Loading conversations...");
    try {
      debugPrint("[Flutter] Calling fetchMessages(50)...");
      await DenDenBridge().fetchMessages(50); 
      debugPrint("[Flutter] fetchMessages done. Getting conversations...");
      
      final jsonStr = await DenDenBridge().getConversations();
      debugPrint("[Flutter] Got conversations JSON: $jsonStr");
      
      final list = jsonDecode(jsonStr) as List<dynamic>;
      
      if (mounted) {
        setState(() {
          _conversations = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("[Flutter] Error loading conversations: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Public method for external refresh
  Future<void> refresh() async {
    setState(() => _isLoading = true);
    await _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    if (_conversations.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Messages"),
        ),
        body: RefreshIndicator(
          onRefresh: _loadConversations,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mail_outline, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('No messages yet', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Pull to refresh', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),
      ), // Inner AppBar
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(), // Ensure scrolling even with few items
          itemCount: _conversations.length,
          itemBuilder: (context, index) {
            final conv = _conversations[index];
            return _ConversationItem(
              pubkey: conv['partner_pubkey'],
              name: conv['partner_name'] ?? '',
              avatar: conv['partner_avatar'] ?? '',
              lastMessage: conv['last_message'],
              timestamp: conv['timestamp'],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(
                      partnerPubkey: conv['partner_pubkey'],
                      partnerName: conv['partner_name'] ?? '',
                      partnerAvatar: conv['partner_avatar'] ?? '',
                    ),
                  ),
                ).then((_) => _loadConversations());
              },
            );
          },
        ),
      ),
    );
  }
}

class _ConversationItem extends StatelessWidget {
  final String pubkey;
  final String name;
  final String avatar;
  final String lastMessage;
  final int timestamp;
  final VoidCallback onTap;

  const _ConversationItem({
    required this.pubkey,
    required this.name,
    required this.avatar,
    required this.lastMessage,
    required this.timestamp,
    required this.onTap,
  });

  String _formatTime(int ts) {
    if (ts <= 0) return "";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    if (now.difference(dt).inHours < 24 && now.day == dt.day) {
      return "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
    }
    return "${dt.month}/${dt.day}";
  }

  @override
  Widget build(BuildContext context) {
    final displayName = name.isNotEmpty ? name : '${pubkey.substring(0, 8)}...';
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: onTap,
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
        child: avatar.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 28) : null,
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        maxLines: 1, 
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      ),
      trailing: Text(
        _formatTime(timestamp),
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
    );
  }
}
