import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../ffi/bridge.dart';
import '../screens/user_detail_screen.dart';
import '../utils/global_cache.dart'; // Centralized cache

/// PostHeader - Displays user avatar, name, and timestamp
/// Extracted from PostItem for modularity and stability
class PostHeader extends StatefulWidget {
  final String pubkey;
  final String myPubkey;
  final DateTime time;
  final String? locationText;

  const PostHeader({
    super.key,
    required this.pubkey,
    required this.myPubkey,
    required this.time,
    this.locationText,
  });

  @override
  State<PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends State<PostHeader> {
  String _displayName = '';
  String _avatarUrl = '';
  Timer? _retryTimer;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _displayName = widget.pubkey.length > 8 
        ? widget.pubkey.substring(0, 8) 
        : widget.pubkey;
    _loadProfile();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    // 1. Check if this is ME - load from local storage immediately
    if (widget.myPubkey.isNotEmpty && widget.pubkey == widget.myPubkey) {
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

    // 3. Start retry loop for others
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _retryCount >= 5) {
        timer.cancel();
        return;
      }
      _retryCount++;
      // Trigger profile fetch from bridge
      DenDenBridge().getProfile(widget.pubkey);
      if (_checkCache()) timer.cancel();
    });
  }

  bool _checkCache() {
    if (globalProfileCache.containsKey(widget.pubkey)) {
      final cached = globalProfileCache[widget.pubkey];
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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        GestureDetector(
          onTap: () => _navigateToProfile(context),
          child: _buildAvatar(),
        ),
        const SizedBox(width: 12),
        // Name + Time + Location
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    _formatTime(widget.time),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  // Location display
                  if (widget.locationText != null) ...[
                    Text(' • ', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    Icon(Icons.location_on, size: 12, color: Colors.grey[600]),
                    Text(widget.locationText!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailScreen(
          pubkey: widget.pubkey,
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
    final int hash = widget.pubkey.hashCode;
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

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
