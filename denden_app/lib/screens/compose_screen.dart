import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../ffi/bridge.dart';
import '../utils/location_service.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _mediaUrls = [];
  final List<File> _previewFiles = [];
  bool _isPosting = false;
  final ImagePicker _picker = ImagePicker();

  final int _charLimit = 280;

  // Location state
  List<String>? _locationTag;
  bool _isLoadingLocation = false;

  // Request photo permission and pick images
  Future<void> _pickImages() async {
    // Request photo library permission first
    var status = await Permission.photos.request();
    
    // Handle permanently denied
    if (status.isPermanentlyDenied) {
      if (mounted) {
        _showPermissionDialog(
          'Photo Access Denied',
          'Please enable photo access in Settings to upload images.',
        );
      }
      return;
    }
    
    if (!status.isGranted && !status.isLimited) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo library access required')),
        );
      }
      return;
    }

    final List<XFile> images = await _picker.pickMultiImage(
      limit: 20,
      imageQuality: 80,
    );

    if (images.isNotEmpty) {
      for (var img in images) {
        final file = File(img.path);
        setState(() => _previewFiles.add(file));
        _uploadToCatbox(file);
      }
    }
  }

  // Upload with network timeout handling
  Future<void> _uploadToCatbox(File file) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://catbox.moe/user/api.php'));
      request.fields['reqtype'] = 'fileupload';
      request.files.add(await http.MultipartFile.fromPath('fileToUpload', file.path));
      
      // Send with timeout
      var response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Upload timeout');
        },
      );
      
      if (response.statusCode == 200) {
        final url = await response.stream.bytesToString();
        if (_previewFiles.any((f) => f.path == file.path)) {
          _mediaUrls.add(url.trim());
        }
      }
    } on SocketException catch (_) {
      // Network error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network timeout. Please check your connection.')),
        );
      }
    } catch (e) {
      debugPrint('Upload failed: $e');
      if (mounted && e.toString().contains('timeout')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload timeout. Please try again.')),
        );
      }
    }
  }

  // Toggle location on/off
  Future<void> _toggleLocation() async {
    if (_locationTag != null) {
      setState(() => _locationTag = null);
      return;
    }

    setState(() => _isLoadingLocation = true);

    try {
      // Check current permission status
      var status = await Permission.locationWhenInUse.status;
      
      // Handle permanently denied - show settings dialog
      if (status.isPermanentlyDenied) {
        if (mounted) {
          setState(() => _isLoadingLocation = false);
          _showPermissionDialog(
            'Location Disabled',
            'Location access is disabled. Open Settings to enable?',
          );
        }
        return;
      }

      // Request permission if not granted
      if (!status.isGranted) {
        bool hasPermission = await LocationService.requestLocationPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission required')),
            );
            setState(() => _isLoadingLocation = false);
          }
          return;
        }
      }

      // Get location tag
      final tag = await LocationService.getCurrentLocationTag();

      if (mounted) {
        setState(() {
          _locationTag = tag;
          _isLoadingLocation = false;
        });
        
        if (tag == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location timeout. Please try again.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location')),
        );
      }
    }
  }

  // Show permission settings dialog
  void _showPermissionDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePost() async {
    if (_controller.text.length > _charLimit) return;
    if (_controller.text.trim().isEmpty && _previewFiles.isEmpty) return;

    setState(() => _isPosting = true);

    if (_previewFiles.length > _mediaUrls.length) {
      await Future.delayed(const Duration(seconds: 2));
    }

    String content = _controller.text.trim();
    if (_mediaUrls.isNotEmpty) {
      content += "\n\n${_mediaUrls.join('\n')}";
    }

    try {
      // Build tags array
      List<List<String>>? tags;
      
      if (_locationTag != null && _locationTag!.length >= 3) {
        // Add location to content for display (temporary until proper tag parsing)
        content += "\n\n📍 ${_locationTag![2]}";
        
        // Also send as proper Nostr 'g' tag
        tags = [_locationTag!];
        debugPrint('🚀 Sending with location tag: $_locationTag');
      }

      await DenDenBridge().publishTextNote(content, tags: tags);
      
      if (mounted) {
        // Clear location state after successful post
        final sentLocationTag = _locationTag;
        setState(() => _locationTag = null);
        
        Navigator.pop(context, {
          'content': content,
          'success': true,
          'locationTag': sentLocationTag,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int currentLength = _controller.text.length;
    bool isOverLimit = currentLength > _charLimit;
    bool hasLocation = _locationTag != null;
    String? cityName = hasLocation ? _locationTag![2] : null;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.black, fontSize: 16)),
        ),
        leadingWidth: 80,
        title: const Text('Den Den', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: (_isPosting || isOverLimit) ? null : _handlePost,
              child: _isPosting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      'Post',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: (_isPosting || isOverLimit) ? Colors.grey : Colors.blue,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _controller,
                maxLength: null,
                maxLines: null,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: "What's new?",
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 16, color: Colors.grey),
                  counterText: "",
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),

          // Image preview
          if (_previewFiles.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _previewFiles.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      Container(
                        width: 180,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: FileImage(_previewFiles[index]),
                            fit: BoxFit.cover,
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 20,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (index < _mediaUrls.length) _mediaUrls.removeAt(index);
                              _previewFiles.removeAt(index);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          // Bottom toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[200]!))),
            child: Row(
              children: [
                // Gallery button
                IconButton(
                  icon: const Icon(Icons.image_outlined, color: Colors.purple),
                  onPressed: _pickImages,
                ),

                // Location button
                _isLoadingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: Icon(
                          hasLocation ? Icons.location_on : Icons.location_on_outlined,
                          color: hasLocation ? Colors.blue : Colors.grey,
                        ),
                        onPressed: _toggleLocation,
                      ),

                // Location badge
                if (hasLocation && cityName != null)
                  GestureDetector(
                    onTap: _toggleLocation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(cityName, style: const TextStyle(color: Colors.blue, fontSize: 12)),
                          const SizedBox(width: 4),
                          const Icon(Icons.close, size: 12, color: Colors.blue),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),

                // Character count
                Row(
                  children: [
                    Text(
                      "$currentLength",
                      style: TextStyle(
                        color: isOverLimit ? Colors.red : Colors.grey,
                        fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const Text(" / 280", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}