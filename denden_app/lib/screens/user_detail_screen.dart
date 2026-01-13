import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'dart:convert';
import 'user_list_screen.dart';
import '../models/nostr_post.dart';
import '../widgets/post_item.dart';
import '../widgets/reply_thread_item.dart';
import '../screens/thread_screen.dart';
import '../screens/chat_detail_screen.dart';

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

class _UserDetailScreenState extends State<UserDetailScreen> with SingleTickerProviderStateMixin {
  String _name = '';
  String _about = '';
  String _picture = '';
  String _banner = '';
  bool _isLoading = true;

  bool _isFollowing = false;
  List<String> _followersList = [];
  List<String> _followingList = [];
  bool _isActionLoading = false;

  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _name = widget.initialName;
    _picture = widget.initialPicture;
    // 5 Tabs: Posts, Replies, Highlights, Media, Reposts
    _tabController = TabController(length: 5, vsync: this);
    
    _fetchUserProfile();
    _fetchSocialStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final bridge = DenDenBridge();
      // Try fetch first for fresh data or use cache logic?
      // Use getProfile cache
      final profileJson = await bridge.getProfile(widget.pubkey);
      final profile = json.decode(profileJson);

      if (profile['cached'] == true) {
         if (mounted) {
          setState(() {
            _name = profile['name'] as String? ?? '';
            _about = profile['about'] as String? ?? '';
            _picture = profile['picture'] as String? ?? '';
            _banner = profile['banner'] as String? ?? '';
            _isLoading = false;
          });
        }
      } else {
        await bridge.fetchProfile(widget.pubkey);
        // Poll or just wait for next update?
        // Simulating simple load complete for now to unblock UI
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
       if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSocialStats() async {
    try {
      final bridge = DenDenBridge();
      final following = await bridge.getFollowing(widget.pubkey);
      final followers = await bridge.getFollowers(widget.pubkey);
      
      String? myPubkey;
      try {
        final identityJson = await bridge.getIdentity();
        myPubkey = jsonDecode(identityJson)['publicKey'];
      } catch (_) {}

      bool isFollowing = false;
      if (myPubkey != null) {
        final myFollowing = await bridge.getFollowing(myPubkey);
        isFollowing = myFollowing.contains(widget.pubkey);
      }

      if (mounted) {
        setState(() {
          _followingList = following;
          _followersList = followers;
          _isFollowing = isFollowing;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    setState(() => _isActionLoading = true);
    try {
      final bridge = DenDenBridge();
      if (_isFollowing) {
        await bridge.unfollow(widget.pubkey);
      } else {
        await bridge.follow(widget.pubkey);
      }
      await _fetchSocialStats(); // Refresh stats
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Twitter Header dimensions
    // Banner height
    const double bannerHeight = 150.0;
    // Avatar radius (diameter 80)
    const double avatarRadius = 40.0;
    const double avatarDiameter = avatarRadius * 2;
    // Avatar overlaps half of the banner bottom
    // So visual height reserved is BannerHeight + (AvatarHeight / 2) + extra padding
    
    return Scaffold(
      body: Stack(
        children: [
          // 1. The main scrollable content
          NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                // We use SliverToBoxAdapter for the Banner+Avatar stack
                // This ensures they scroll together and Z-order is managed by the Stack widget
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(
                        height: bannerHeight + avatarRadius + 20, // Increased to accommodate button (150+40+20 = 210)
                        child: Stack(
                          children: [
                            // BANNER (Top)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: bannerHeight,
                              child: _banner.isNotEmpty
                                  ? Image.network(
                                      _banner,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(color: Colors.grey[850]),
                                    )
                                  : Container(color: Colors.grey[850]),
                            ),
                            
                            // AVATAR (Overlapping bottom left)
                            Positioned(
                              top: bannerHeight - avatarRadius, // 110
                              left: 16,
                              child: Container(
                                width: avatarDiameter,
                                height: avatarDiameter,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 4),
                                ),
                                child: CircleAvatar(
                                  radius: avatarRadius,
                                  backgroundColor: Colors.grey[300],
                                  backgroundImage: _picture.isNotEmpty ? NetworkImage(_picture) : null,
                                  child: _picture.isEmpty ? Icon(Icons.person, size: 40, color: Colors.grey[600]) : null,
                                ),
                              ),
                            ),
                            
                            // ACTIONS (Message + Follow)
                            Positioned(
                              top: bannerHeight + 10,
                              right: 16,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Message Button
                                  Container(
                                    width: 36,
                                    height: 36,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.mail_outline, size: 20, color: Colors.black),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChatDetailScreen(
                                              partnerPubkey: widget.pubkey,
                                              partnerName: _name,
                                              partnerAvatar: _picture,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: _isActionLoading ? null : _toggleFollow,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _isFollowing ? Colors.transparent : Colors.black,
                                      foregroundColor: _isFollowing ? Colors.black : Colors.white,
                                      side: _isFollowing ? const BorderSide(color: Colors.grey) : null,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0), // Pill shape
                                    ).copyWith(elevation: ButtonStyleButton.allOrNull(0)),
                                    child: _isActionLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Text(_isFollowing ? 'Following' : 'Follow', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // PROFILE INFO (Name, Bio, Stats)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             // Removed extra SizedBox(height: 8) as header is taller now
                             Text(
                                _name.isNotEmpty ? _name : 'Anonymous',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.pubkey.length > 12 
                                  ? '${widget.pubkey.substring(0, 6)}...${widget.pubkey.substring(widget.pubkey.length - 6)}' 
                                  : widget.pubkey,
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                              const SizedBox(height: 12),
                              if (_about.isNotEmpty) ...[
                                Text(_about),
                                const SizedBox(height: 12),
                              ],
                              Row(
                                children: [
                                  _buildStatItem('${_followingList.length}', 'Following'),
                                  const SizedBox(width: 16),
                                  _buildStatItem('${_followersList.length}', 'Followers'),
                                ],
                              ),
                              const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Sticky Tab Bar
                SliverPersistentHeader(
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.black, 
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.blue,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent, // Remove default divider line
                      isScrollable: false, // Fill the width
                      labelPadding: EdgeInsets.zero, // Use default distribution
                      tabs: const [
                        Tab(text: "Posts"),
                        Tab(text: "Replies"),
                        Tab(text: "Highlights"),
                        Tab(text: "Media"),
                        Tab(text: "Reposts"),
                      ],
                    ),
                  ),
                  pinned: true,
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                 _FeedTab(
                  pubkey: widget.pubkey,
                  fetcher: (pubkey) => DenDenBridge().getUserPosts(pubkey), // Excludes Kind 6
                  emptyMessage: "No posts yet",
                ),
                 _FeedTab(
                  pubkey: widget.pubkey,
                  fetcher: (pubkey) => DenDenBridge().getUserRepliesWithProfile(pubkey),
                  emptyMessage: "No replies yet",
                  isRepliesTab: true, 
                ),
                 _FeedTab(
                  pubkey: widget.pubkey,
                  fetcher: (pubkey) => DenDenBridge().getUserHighlights(pubkey),
                  emptyMessage: "No highlights yet",
                ),
                 _FeedTab(
                  pubkey: widget.pubkey,
                  fetcher: (pubkey) => DenDenBridge().getUserMedia(pubkey),
                  emptyMessage: "No media yet",
                ),
                 _FeedTab(
                  pubkey: widget.pubkey,
                  fetcher: (pubkey) => DenDenBridge().getUserReposts(pubkey),
                  emptyMessage: "No reposts yet",
                ),
              ],
            ),
          ),
          
          // 2. Floating Back Button (Smaller)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                   Container(
                      margin: const EdgeInsets.all(8),
                      width: 32, // Smaller size
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero, // Remove padding
                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
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

  Widget _buildStatItem(String count, String label) {
    return Row(
      children: [
        Text(count, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: Colors.grey[300]!, width: 0.5)),
      ),
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

// Reusable Feed Tab
class _FeedTab extends StatefulWidget {
  final String pubkey;
  final Future<String> Function(String) fetcher;
  final String emptyMessage;
  final bool isRepliesTab; 

  const _FeedTab({
    required this.pubkey,
    required this.fetcher,
    required this.emptyMessage,
    this.isRepliesTab = false,
  });

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> with AutomaticKeepAliveClientMixin {
  List<NostrPost> _posts = [];
  bool _isLoading = true;
  String? _myPubkey;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchFeed();
    _fetchMyIdentity();
  }

  Future<void> _fetchMyIdentity() async {
    try {
      final json = await DenDenBridge().getIdentity();
      final data = jsonDecode(json);
      if (mounted) setState(() => _myPubkey = data['publicKey']);
    } catch (_) {}
  }

  Future<void> _fetchFeed() async {
    try {
      final jsonStr = await widget.fetcher(widget.pubkey);
      final List<dynamic> list = jsonDecode(jsonStr);
      final posts = list.map((e) => NostrPost.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(widget.emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _posts.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final post = _posts[index];
        if (_myPubkey == null) return const SizedBox.shrink();
        
        if (widget.isRepliesTab) {
           return ReplyThreadItem(
             replyPost: post,
             myPubkey: _myPubkey!,
             onTap: () => _navigateToThread(post),
           );
        }

        return PostItem(
          post: post,
          myPubkey: _myPubkey!,
          onTap: () => _navigateToThread(post),
        );
      },
    );
  }

  void _navigateToThread(NostrPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ThreadScreen(
          rootPost: post,
          myPubkey: _myPubkey!,
        ),
      ),
    );
  }
}
