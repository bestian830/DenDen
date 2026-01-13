import 'package:flutter/material.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              // TODO: Add friend
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildSystemItem(Icons.person_add, 'New Friends', Colors.orange),
          _buildSystemItem(Icons.group, 'Group Chats', Colors.green),
          _buildSystemItem(Icons.label, 'Tags', Colors.blue),
          _buildSystemItem(Icons.public, 'Official Accounts', Colors.blueAccent),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text("Friends", style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          // TODO: Load actual contacts
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text("No contacts yet", style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemItem(IconData icon, String label, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(label),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () {},
    );
  }
}
