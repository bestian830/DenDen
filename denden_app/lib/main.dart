import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'package:denden_app/screens/compose_screen.dart';
import 'package:denden_app/screens/profile_screen.dart';
import 'package:denden_app/screens/home_feed.dart';
import 'package:denden_app/screens/chat_list_screen.dart';
import 'package:denden_app/screens/contact_screen.dart'; // NEW
import 'package:denden_app/screens/notification_screen.dart'; // NEW
import 'package:denden_app/utils/global_cache.dart'; // Centralized cache
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const DenDenApp());
}

class DenDenApp extends StatelessWidget {
  const DenDenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Den Den',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String _publicKey = '';
  String _name = '';
  String _picture = '';
  String _about = '';
  String _banner = ''; // Added for banner
  String _website = ''; // Added for website
  bool _isConnecting = false;
  Timer? _profileRetryTimer;

  final ScrollController _homeScrollController = ScrollController();
  final GlobalKey<HomeFeedState> _homeFeedKey = GlobalKey();
  final GlobalKey<ChatListScreenState> _chatListKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeDenDen();
  }
  

  Future<void> _initializeDenDen() async {
    try {
      final bridge = DenDenBridge();
      await bridge.initialize();
      final identityJson = await bridge.getIdentity();
      final identity = json.decode(identityJson);

      final pubkey = identity['publicKey'] ?? '';
      if (mounted) setState(() => _publicKey = pubkey);

      await _fetchMyProfile(pubkey);

      if (mounted) setState(() => _isConnecting = true);
      await bridge.connectToDefault();
      if (mounted) setState(() => _isConnecting = false);
    } catch (e) {
      debugPrint('Init Error: $e');
    }
  }

  Future<void> _fetchMyProfile(String pubkey) async {
    if (pubkey.isEmpty) return;

    // 1. FAST: Check Global Memory Cache first (all 5 fields)
    if (globalProfileCache.containsKey(pubkey)) {
      final cached = globalProfileCache[pubkey]!;
      if (mounted) {
        setState(() {
          _name = cached['name'] ?? '';
          _picture = cached['picture'] ?? '';
          _about = cached['about'] ?? '';
          _banner = cached['banner'] ?? '';
          _website = cached['website'] ?? '';
        });
      }
    }

    // 2. MEDIUM: Check Disk (SharedPreferences) - all 5 fields
    final prefs = await SharedPreferences.getInstance();
    final localName = prefs.getString('profile_name');
    final localPic = prefs.getString('profile_picture');
    final localAbout = prefs.getString('profile_about');
    final localBanner = prefs.getString('profile_banner');
    final localWebsite = prefs.getString('profile_website');
    
    if (localName != null && localName.isNotEmpty && _name.isEmpty) {
      if (mounted) {
        setState(() {
          _name = localName;
          _picture = localPic ?? '';
          _about = localAbout ?? '';
          _banner = localBanner ?? '';
          _website = localWebsite ?? '';
        });
      }
      // Sync disk data to global cache immediately
      globalProfileCache[pubkey] = {
        'name': localName,
        'picture': localPic ?? '',
        'about': localAbout ?? '',
        'banner': localBanner ?? '',
        'website': localWebsite ?? '',
      };
    }

    // 3. SLOW: Check Network (Bridge) - all 5 fields
    try {
      final bridge = DenDenBridge();
      final profileJson = await bridge.getProfile(pubkey);
      final profile = json.decode(profileJson);
      
      // Accept any valid profile response
      if (profile != null) {
        final newName = profile['name'] as String? ?? '';
        final newPicture = profile['picture'] as String? ?? '';
        final newAbout = profile['about'] as String? ?? '';
        final newBanner = profile['banner'] as String? ?? '';
        final newWebsite = profile['website'] as String? ?? '';
        
        // Only update if we got real data
        if (newName.isNotEmpty) {
          // Update EVERYTHING (UI, Global Cache, Disk)
          globalProfileCache[pubkey] = {
            'name': newName,
            'picture': newPicture,
            'about': newAbout,
            'banner': newBanner,
            'website': newWebsite,
          };
          await prefs.setString('profile_name', newName);
          await prefs.setString('profile_picture', newPicture);
          await prefs.setString('profile_about', newAbout);
          await prefs.setString('profile_banner', newBanner);
          await prefs.setString('profile_website', newWebsite);
          
          if (mounted) {
            setState(() {
              _name = newName;
              _picture = newPicture;
              _about = newAbout;
              _banner = newBanner;
              _website = newWebsite;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Profile network fetch error: $e');
    }

    // 4. RETRY: Poll cache every 1s for up to 10s (for async network updates)
    if (_name.isEmpty) {
      _profileRetryTimer?.cancel();
      _profileRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || timer.tick > 10) {
          timer.cancel();
          return;
        }
        if (globalProfileCache.containsKey(pubkey)) {
          final cached = globalProfileCache[pubkey]!;
          final cachedName = cached['name'] ?? '';
          if (cachedName.isNotEmpty) {
            timer.cancel();
            setState(() {
              _name = cachedName;
              _picture = cached['picture'] ?? '';
              _about = cached['about'] ?? '';
              _banner = cached['banner'] ?? '';
              _website = cached['website'] ?? '';
            });
          }
        }
      });
    }
  }

  void _scrollToTop() {
    _homeScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: (_selectedIndex == 2 || _selectedIndex == 3)
        ? null // Hide outer AppBar on Contacts (2) and Messages (3) tabs
        : AppBar(
        title: GestureDetector(
          onTap: _scrollToTop,
          child: const Text('DenDen'),
        ),
        centerTitle: true,
        actions: [
          if (_isConnecting)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.purple),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      backgroundImage: _picture.isNotEmpty ? NetworkImage(_picture) : null,
                      child: _picture.isEmpty
                          ? Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(_name.isNotEmpty ? _name : 'Anonymous',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      _publicKey.length > 16 ? '${_publicKey.substring(0, 16)}...' : _publicKey,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProfileScreen(currentName: _name, currentAbout: _about, currentPicture: _picture, currentBanner: _banner, currentWebsite: _website)),
                  );
                  if (result == true) {
                    _fetchMyProfile(_publicKey);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomeFeed(
            key: _homeFeedKey,
            scrollController: _homeScrollController,
            myPubkey: _publicKey,
          ),
          const Center(child: Text('Search')),
          const NotificationScreen(), // Replaced Contacts with Notifications
          ChatListScreen(key: _chatListKey),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 0 && _selectedIndex == 0) {
            _scrollToTop();
          } else if (index == 3 && _selectedIndex == 3) {
             _chatListKey.currentState?.refresh();
          }
          setState(() => _selectedIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), label: 'Notifs'), // Reverted Icon
          BottomNavigationBarItem(icon: Icon(Icons.mail_outline), label: 'DMs'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ComposeScreen()),
          );

          if (result != null && result is Map && result['success'] == true) {
            _scrollToTop();
            final content = result['content'] as String;
            _homeFeedKey.currentState?.insertMyPost(content, _publicKey);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Post published!')),
            );
          }
        },
      ),
    );
  }
}