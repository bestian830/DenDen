import 'package:flutter/material.dart';

class MediaCarousel extends StatefulWidget {
  final List<String> urls;

  const MediaCarousel({super.key, required this.urls});

  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<MediaCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();

    // Single image mode: display rounded large image
    if (widget.urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          widget.urls.first,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (ctx, _, __) => Container(
            height: 200,
            color: Colors.grey[200],
            child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          ),
        ),
      );
    }

    // Multi-image mode: Threads-style carousel (horizontal swipe)
    return Column(
      children: [
        SizedBox(
          height: 300, // Fixed height, Threads-style experience
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.urls[index],
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, _, __) => Container(color: Colors.grey[200]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Bottom dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.urls.length, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == index ? 8 : 6,
              height: _currentPage == index ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index ? Colors.purple : Colors.grey[300],
              ),
            );
          }),
        ),
      ],
    );
  }
}
