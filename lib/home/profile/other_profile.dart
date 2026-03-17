import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:ui'; // For ImageFilter
import 'package:flutter_app/config/config.dart';

class OtherUserProfilePage extends StatefulWidget {
  final int    userId;
  final String userName;

  const OtherUserProfilePage({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<OtherUserProfilePage> createState() => _OtherUserProfilePageState();
}

class _OtherUserProfilePageState extends State<OtherUserProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool   _isLoading     = true;
  bool   _isFollowing   = false;
  bool   _followLoading = false;
  bool   _isOwnProfile  = false;

  String name           = '';
  String bio            = ''; 
  String? profilePicture;     
  int    postCount      = 0;
  int    tripCount      = 0;
  int    followerCount  = 0;
  int    followingCount = 0;
  List   posts          = [];
  List   trips          = [];
  List<Map<String, dynamic>> groupedPosts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  String _getValidImageUrl(dynamic imageUrl) {
    if (imageUrl == null) return '';

    String url = imageUrl.toString().trim();
    if (url.isEmpty) return '';

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    try {
      final supabase = Supabase.instance.client;
      return supabase.storage.from('post-image').getPublicUrl(url);
    } catch (e) {
      debugPrint('Error constructing image URL: $e');
      return url;
    }
  }

  List<Map<String, dynamic>> _groupPostsByTrip(List<dynamic> postsList) {
    Map<String, Map<String, dynamic>> tripGroups = {};

    for (var post in postsList) {
      if (post is Map) {
        String tripKey = 'unknown';
        String tripName = post['trip_display']?.toString() ?? 'Unknown Trip';
        int? tripId;

        if (post['trip'] != null && post['trip'] is Map) {
          tripId = post['trip']['id'];
          tripName = post['trip']['destination']?.toString() ?? tripName;
          tripKey = 'trip_$tripId';
        } else if (post['trip_id'] != null) {
          tripId = post['trip_id'];
          tripKey = 'trip_$tripId';
        } else if (post['trip_display'] != null) {
          tripKey = tripName;
        } else if (post['destination'] != null) {
          tripName = post['destination'].toString();
          tripKey = tripName;
        }

        String imageUrl = post['display_image_url']?.toString() ?? 
                          _getValidImageUrl(post['image_url']);

        if (!tripGroups.containsKey(tripKey)) {
          tripGroups[tripKey] = {
            'trip_id': tripId,
            'trip_name': tripName,
            'images': [],
            'first_image': imageUrl,
            'post_ids': [],
            'trip_details': post['trip_details'] ?? post['trip'],
          };
        }

        if (imageUrl.isNotEmpty) {
          tripGroups[tripKey]!['images'].add({
            'url': imageUrl,
            'post_id': post['id'],
            'caption': post['caption'] ?? '',
          });
        }

        if (post['id'] != null) {
          tripGroups[tripKey]!['post_ids'].add(post['id']);
        }
      }
    }
    return tripGroups.values.toList();
  }

  Future<void> _loadProfile() async {
    // Only show full loading spinner on initial load, not on pull-to-refresh
    if (posts.isEmpty) {
      setState(() => _isLoading = true);
    }
    
    try {
      final token    = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/profile/${widget.userId}/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        final rawPosts = data['posts'] ?? [];
        final processedPosts = (rawPosts as List).map((post) {
          if (post is Map) {
            String imageUrl = post['image_url']?.toString() ?? 
                              post['url']?.toString() ?? 
                              post['image']?.toString() ?? '';
            final validUrl = _getValidImageUrl(imageUrl);

            // Robust Trip Parsing
            String tripDestination = 'Unknown Trip';
            int? tripId;
            Map<String, dynamic>? tripDetails;

            if (post['trip'] != null) {
              if (post['trip'] is Map) {
                tripDetails = Map<String, dynamic>.from(post['trip']);
                if (tripDetails['destination'] != null) {
                  tripDestination = tripDetails['destination'].toString();
                }
                if (tripDetails['id'] != null) {
                  tripId = tripDetails['id'];
                }
              }
            }
            
            // Fallbacks
            if (tripDestination == 'Unknown Trip' && post['trip_destination'] != null) {
              tripDestination = post['trip_destination'].toString();
            }
            if (tripDestination == 'Unknown Trip' && post['destination'] != null) {
              tripDestination = post['destination'].toString();
            }

            return {
              ...post,
              'display_image_url': validUrl,
              'trip_display': tripDestination,
              'trip_id': tripId,
              'trip_details': tripDetails ?? post['trip'],
            };
          }
          return post;
        }).toList();

        final grouped = _groupPostsByTrip(processedPosts);

        setState(() {
          name           = data['name'] ?? widget.userName;
          bio            = data['bio']?.toString() ?? '';
          profilePicture = data['profile_picture']?.toString();
          
          postCount      = processedPosts.length;
          tripCount      = data['trip_count'] ?? 0;
          followerCount  = data['follower_count'] ?? 0;
          followingCount = data['following_count'] ?? 0;
          posts          = rawPosts;
          trips          = data['trips'] ?? [];
          groupedPosts   = grouped;
          _isFollowing   = data['is_following'] ?? false;
          _isOwnProfile  = data['is_own_profile'] ?? false;
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile: ${response.statusCode}')),
        );
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _followLoading = true);
    try {
      final token    = await _getToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/follow/${widget.userId}/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isFollowing  = data['following'];
          followerCount = _isFollowing ? followerCount + 1 : followerCount - 1;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFollowing ? 'Following ${name.isNotEmpty ? name : widget.userName}' : 'Unfollowed'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Follow error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  void _showTripAlbum(Map<String, dynamic> tripAlbum, {int initialIndex = 0}) {
    final images = tripAlbum['images'] as List;
    if (images.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        int currentIndex = initialIndex;
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(0),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.network(
                    images[currentIndex]['url'],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.3)),
                ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.transparent),
                ),

                Column(
                  children: [
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tripAlbum['trip_name'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${images.length} ${images.length == 1 ? 'photo' : 'photos'}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.8),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 22),
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Expanded(
                      child: PageView.builder(
                        itemCount: images.length,
                        controller: PageController(initialPage: currentIndex),
                        onPageChanged: (index) => setState(() => currentIndex = index),
                        itemBuilder: (_, index) {
                          return InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.network(
                                images[index]['url'],
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                          : null,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image, color: Colors.white.withOpacity(0.7), size: 50),
                                    const SizedBox(height: 8),
                                    Text('Failed to load image', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (images.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                                ),
                                child: Text(
                                  '${currentIndex + 1} / ${images.length}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.black))
            : RefreshIndicator(
                onRefresh: _loadProfile,
                color: Colors.black,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh always works
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.arrow_back_ios, size: 20),
                              ),
                            ),
                            Text(
                              name.isNotEmpty ? name : widget.userName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 10)),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isNotEmpty ? name : widget.userName,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  if (bio.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      bio,
                                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 15),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: const Color(0xFFF5F5F5),
                                backgroundImage: profilePicture != null && profilePicture!.isNotEmpty
                                    ? NetworkImage(profilePicture!)
                                    : null,
                                child: profilePicture == null || profilePicture!.isEmpty
                                    ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    if (!_isOwnProfile)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _followLoading ? null : _toggleFollow,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFollowing ? Colors.white : Colors.black,
                                foregroundColor: _isFollowing ? Colors.black : Colors.white,
                                elevation: 0,
                                side: _isFollowing ? const BorderSide(color: Colors.black) : BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _followLoading
                                  ? const SizedBox(
                                      height: 18, width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : Text(
                                      _isFollowing ? 'Following' : 'Follow',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(postCount.toString(),      'Posts'),
                          _StatItem(tripCount.toString(),      'Trips'),
                          _StatItem(followerCount.toString(),  'Followers'),
                          _StatItem(followingCount.toString(), 'Following'),
                        ],
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 20)),

                    SliverToBoxAdapter(
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: Colors.black,
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.grey,
                        tabs: const [
                          Tab(text: 'Trips'),
                          Tab(text: 'Posts'),
                        ],
                      ),
                    ),

                    SliverFillRemaining(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // ── Trips tab ──────────────────────────────────────
                          trips.isEmpty
                              ? Center(child: _emptyState(Icons.luggage, 'No trips yet'))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: trips.length,
                                  itemBuilder: (context, index) {
                                    final trip = trips[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          backgroundColor: Colors.black,
                                          child: Icon(Icons.location_on, color: Colors.white, size: 18),
                                        ),
                                        title: Text(
                                          trip['destination'] ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(trip['start_date'] ?? ''),
                                      ),
                                    );
                                  },
                                ),

                          // ── Posts (Albums) tab ─────────────────────────────
                          groupedPosts.isEmpty
                              ? Center(child: _emptyState(Icons.photo_library, 'No posts yet'))
                              : GridView.builder(
                                  padding: const EdgeInsets.all(10),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 5,
                                    mainAxisSpacing: 5,
                                  ),
                                  itemCount: groupedPosts.length,
                                  itemBuilder: (context, index) {
                                    final album = groupedPosts[index];
                                    final images = album['images'] as List;
                                    final firstImage = album['first_image'] ?? (images.isNotEmpty ? images[0]['url'] : '');
                                    final imageCount = images.length;
                                    final tripName = album['trip_name'] ?? 'Unknown Trip';

                                    return GestureDetector(
                                      onTap: () => _showTripAlbum(album),
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: firstImage.isEmpty
                                                ? Container(
                                                    color: Colors.grey[200],
                                                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                                  )
                                                : Image.network(
                                                    firstImage,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    loadingBuilder: (context, child, loadingProgress) {
                                                      if (loadingProgress == null) return child;
                                                      return Container(
                                                        color: Colors.grey[200],
                                                        child: Center(
                                                          child: CircularProgressIndicator(
                                                            value: loadingProgress.expectedTotalBytes != null
                                                                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                                : null,
                                                            strokeWidth: 2,
                                                            color: Colors.black,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        color: Colors.grey[200],
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            const Icon(Icons.broken_image, color: Colors.grey, size: 30),
                                                            const SizedBox(height: 4),
                                                            Text('Error', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                          // Folder Icon for Multiple Images
                                          if (imageCount > 1)
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.7),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.folder_copy, color: Colors.white, size: 12),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '$imageCount',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          // Trip Name Overlay
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                              decoration: BoxDecoration(
                                                borderRadius: const BorderRadius.only(
                                                  bottomLeft: Radius.circular(10),
                                                  bottomRight: Radius.circular(10),
                                                ),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                                                ),
                                              ),
                                              child: Text(
                                                tripName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}