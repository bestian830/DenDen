import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'dart:convert';

class UserDetailScreen extends StatefulWidget {
  final String pubkey;
  final String initialName;
  final String initialPicture;

  const UserDetailScreen({
    super.key,
    required this.pubkey,
    this.initialName = '',
    this.initialPicture = '',
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  String _name = '';
  String _about = '';
  String _picture = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _name = widget.initialName;
    _picture = widget.initialPicture;
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final bridge = DenDenBridge();
      final profileJson = await bridge.getProfile(widget.pubkey);
      final profile = json.decode(profileJson);

      if (profile['cached'] == true) {
        setState(() {
          _name = profile['name'] as String? ?? '';
          _about = profile['about'] as String? ?? '';
          _picture = profile['picture'] as String? ?? '';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with banner
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(Icons.image, size: 64, color: Colors.grey),
                ),
              ),
            ),
          ),

          // Profile info
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Large avatar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _picture.isNotEmpty
                            ? NetworkImage(_picture)
                            : null,
                        onBackgroundImageError: _picture.isNotEmpty
                            ? (_, __) {}
                            : null,
                        child: _picture.isEmpty
                            ? Icon(Icons.person, size: 40, color: Colors.grey[600])
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _isLoading
                          ? 'Loading...'
                          : (_name.isNotEmpty ? _name : 'Anonymous'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Public key (shortened)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      widget.pubkey.substring(0, 16) + '...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bio
                  if (_about.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _about,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  const SizedBox(height: 24),

                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Section header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Posts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // User's posts (placeholder for now)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(Icons.article_outlined, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Posts from this user will appear here',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Feature coming soon...',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
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
}
