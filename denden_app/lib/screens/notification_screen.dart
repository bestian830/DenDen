import 'package:flutter/material.dart';
import 'package:denden_app/ffi/bridge.dart';
import 'dart:convert';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final jsonStr = await DenDenBridge().getNotifications();
      final list = jsonDecode(jsonStr) as List<dynamic>;
      if (mounted) {
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text("No notifications"))
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    // TODO: Improve UI
                    return ListTile(
                      leading: const Icon(Icons.notifications),
                      title: Text(notif['content'] ?? 'New notification'),
                      subtitle: Text(notif['pubkey'] ?? ''),
                    );
                  },
                ),
    );
  }
}
