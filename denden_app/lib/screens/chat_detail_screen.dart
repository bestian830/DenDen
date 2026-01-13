import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

class ChatDetailScreen extends StatefulWidget {
  final String partnerPubkey;
  final String? partnerName;
  final String? partnerAvatar;

  const ChatDetailScreen({
    super.key,
    required this.partnerPubkey,
    this.partnerName,
    this.partnerAvatar,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _isLoading = true;
  Timer? _pollTimer;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMessages(refresh: true);
    });
  }

  Future<void> _loadMessages({bool refresh = false}) async {
    try {
      if (!refresh) await DenDenBridge().fetchMessages(50); // Fetch from network initially
      
      final jsonStr = await DenDenBridge().getChatMessages(widget.partnerPubkey);
      final list = jsonDecode(jsonStr) as List<dynamic>;
      
      if (mounted) {
        setState(() {
          _messages = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading chat: $e");
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final success = await DenDenBridge().sendDirectMessage(widget.partnerPubkey, text);
      if (success) {
        _controller.clear();
        _loadMessages(refresh: true);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send')));
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 40,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: widget.partnerAvatar != null && widget.partnerAvatar!.isNotEmpty
                  ? CachedNetworkImageProvider(widget.partnerAvatar!)
                  : null,
              child: (widget.partnerAvatar == null || widget.partnerAvatar!.isEmpty) 
                  ? const Icon(Icons.person, size: 20) : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.partnerName ?? widget.partnerPubkey.substring(0, 8),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(child: Text("Start a secure conversation", style: TextStyle(color: Colors.grey[400])))
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true, // Show bottom first? No, we need to sort by time desc?
                        // If cached list is sorted by time (old->new) as per chat.go,
                        // then reverse: true means index 0 is oldest? No.
                        // chat.go sorts by CreatedAt ASC (old -> new).
                        // So index 0 is old. index last is new.
                        // To stick to bottom, we usually reverse list or use reverse: true.
                        // Let's reverse the list in UI.
                        itemCount: _messages.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemBuilder: (context, index) {
                          final msg = _messages[_messages.length - 1 - index];
                          final bool isMine = msg['is_mine'] == true;
                          
                          // iMessage Style
                          // My messages: Blue background, White text.
                          // Their messages: Grey background, Black text.
                          // No checkmarks.
                          
                          return Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMine ? Colors.blue : const Color(0xFFE9E9EB), // iMessage Grey
                                borderRadius: BorderRadius.circular(20).copyWith(
                                  bottomRight: isMine ? Radius.zero : null,
                                  bottomLeft: !isMine ? Radius.zero : null,
                                ),
                              ),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                              child: Text(
                                msg['content'] ?? '',
                                style: TextStyle(
                                  color: isMine ? Colors.white : Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white, // iMessage input area is white
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'iMessage', // Classic placeholder
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSending ? null : _sendMessage,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: _isSending ? Colors.grey : Colors.blue,
                      child: _isSending 
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
