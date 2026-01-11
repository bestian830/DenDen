import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../ffi/bridge.dart';
import '../utils/global_cache.dart';
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentAbout;
  final String currentPicture;
  final String currentBanner;
  final String currentWebsite;

  const ProfileScreen({
    super.key,
    required this.currentName,
    required this.currentAbout,
    required this.currentPicture,
    this.currentBanner = '',
    this.currentWebsite = '',
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _aboutController;
  late TextEditingController _pictureController;
  late TextEditingController _bannerController;
  late TextEditingController _websiteController;
  bool _isUploading = false;
  bool _isSaving = false;
  String _uploadingFor = ''; // 'avatar' or 'banner'

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _aboutController = TextEditingController(text: widget.currentAbout);
    _pictureController = TextEditingController(text: widget.currentPicture);
    _bannerController = TextEditingController(text: widget.currentBanner);
    _websiteController = TextEditingController(text: widget.currentWebsite);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aboutController.dispose();
    _pictureController.dispose();
    _bannerController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String target) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    
    if (pickedFile != null) {
      _uploadImage(File(pickedFile.path), target);
    }
  }

  Future<void> _uploadImage(File imageFile, String target) async {
    setState(() {
      _isUploading = true;
      _uploadingFor = target;
    });
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://catbox.moe/user/api.php'));
      request.fields['reqtype'] = 'fileupload';
      request.files.add(await http.MultipartFile.fromPath('fileToUpload', imageFile.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        final url = await response.stream.bytesToString();
        setState(() {
          if (target == 'avatar') {
            _pictureController.text = url.trim();
          } else if (target == 'banner') {
            _bannerController.text = url.trim();
          }
        });
        debugPrint("✅ $target uploaded: $url");
      }
    } catch (e) {
      debugPrint("❌ $target upload failed: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed')));
    } finally {
      if (mounted) setState(() {
        _isUploading = false;
        _uploadingFor = '';
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_isUploading || _isSaving) return;

    final name = _nameController.text.trim();
    final about = _aboutController.text.trim();
    final picture = _pictureController.text.trim();
    final banner = _bannerController.text.trim();
    final website = _websiteController.text.trim();

    setState(() => _isSaving = true);
    debugPrint("💾 Saving profile...");

    try {
      // 1. Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_name', name);
      await prefs.setString('profile_about', about);
      await prefs.setString('profile_picture', picture);
      await prefs.setString('profile_banner', banner);
      await prefs.setString('profile_website', website);
      debugPrint("✅ Profile saved locally");

      // 2. Sync to globalProfileCache
      try {
        final identityJson = await DenDenBridge().getIdentity();
        final identity = json.decode(identityJson);
        final pubkey = identity['publicKey'] as String? ?? '';
        if (pubkey.isNotEmpty) {
          globalProfileCache[pubkey] = {
            'name': name,
            'about': about,
            'picture': picture,
            'banner': banner,
            'website': website,
          };
          debugPrint("✅ Profile synced to cache");
        }
      } catch (e) {
        debugPrint("⚠️ Cache sync error: $e");
      }

      // 3. Publish to network (non-blocking)
      try {
        debugPrint("📡 Sending to relay...");
        DenDenBridge().publishMetadata(name, about, picture, banner: banner, website: website).then((_) {
          debugPrint("✅ Metadata published (Kind 0)");
        }).catchError((e) {
          debugPrint("❌ Publish failed: $e");
        });
      } catch (netErr) {
        debugPrint("❌ Network error: $netErr");
      }

      // 4. Return immediately
      if (mounted) {
        debugPrint("🔙 Returning with success");
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("❌ Fatal error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton(
              onPressed: (_isUploading || _isSaving) ? null : _saveProfile,
              style: FilledButton.styleFrom(backgroundColor: Colors.purple, shape: const StadiumBorder()),
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Banner (3:1 aspect ratio)
            GestureDetector(
              onTap: () => _pickImage('banner'),
              child: AspectRatio(
                aspectRatio: 3,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    image: _bannerController.text.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(_bannerController.text),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      if (_bannerController.text.isEmpty)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('Add Banner', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      if (_isUploading && _uploadingFor == 'banner')
                        Container(
                          color: Colors.black26,
                          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: const Icon(Icons.edit, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Avatar (overlapping banner)
            Transform.translate(
              offset: const Offset(0, -40),
              child: GestureDetector(
                onTap: () => _pickImage('avatar'),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _pictureController.text.isNotEmpty ? NetworkImage(_pictureController.text) : null,
                        child: _pictureController.text.isEmpty 
                            ? const Icon(Icons.person, size: 50, color: Colors.grey) 
                            : null,
                      ),
                    ),
                    if (_isUploading && _uploadingFor == 'avatar')
                      const Positioned.fill(
                        child: CircularProgressIndicator(),
                      ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, color: Colors.white, size: 16),
                    ),
                  ],
                ),
              ),
            ),
            
            // Form fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _aboutController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'About',
                      hintText: 'Tell people about yourself...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _websiteController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Website',
                      hintText: 'https://example.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}