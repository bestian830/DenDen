import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'package:denden_app/screens/user_detail_screen.dart';
import 'dart:convert';

class UserListScreen extends StatelessWidget {
  final String title;
  final List<String> pubkeys;

  const UserListScreen({
    super.key,
    required this.title,
    required this.pubkeys,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: pubkeys.isEmpty
          ? Center(
              child: Text(
                'No users found',
                style: TextStyle(color: Colors.grey[500]),
              ),
            )
          : ListView.separated(
              itemCount: pubkeys.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return _UserListItem(pubkey: pubkeys[index]);
              },
            ),
    );
  }
}

class _UserListItem extends StatefulWidget {
  final String pubkey;

  const _UserListItem({required this.pubkey});

  @override
  State<_UserListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<_UserListItem> {
  String _name = '';
  String _picture = '';
  String _about = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final bridge = DenDenBridge();
      // Trigger async fetch
      await bridge.fetchProfile(widget.pubkey);
      
      // Get cached
      final jsonStr = await bridge.getProfile(widget.pubkey);
      final data = json.decode(jsonStr);
      
      if (mounted) {
        setState(() {
          _name = data['name'] as String? ?? '';
          _picture = data['picture'] as String? ?? '';
          _about = data['about'] as String? ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[300],
        backgroundImage: _picture.isNotEmpty ? NetworkImage(_picture) : null,
        child: _picture.isEmpty 
            ? Icon(Icons.person, color: Colors.grey[600]) 
            : null,
      ),
      title: Text(
        _name.isNotEmpty ? _name : widget.pubkey.substring(0, 8),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        _about.isNotEmpty ? _about : widget.pubkey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserDetailScreen(
              pubkey: widget.pubkey,
              initialName: _name,
              initialPicture: _picture,
            ),
          ),
        );
      },
    );
  }
}
