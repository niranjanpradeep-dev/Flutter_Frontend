import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:ui'; // For ImageFilter
import 'dart:io'; // For File upload
import '../../routes.dart';
import 'package:flutter_app/config/config.dart';
import '../profile/edit_profile.dart'; // Ensure this path matches your structure

const String baseUrl = AppConfig.baseUrl;

class UserProfile extends StatefulWidget {
  const UserProfile({Key? key}) : super(key: key);

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String username = 'Loading...';
  String email = 'Loading...';
  String bio = '';
  String? profilePicture;
  int postCount = 0;
  int tripCount = 0;
  int followerCount = 0;
  int followingCount = 0;
  List trips = [];
  List<Map<String, dynamic>> groupedPosts = []; // Grouped by trip
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkAuthStatus();
    fetchProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── AUTH & DATA ───────────────────────────────────────────────────────────

  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null && mounted) {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.login, (route) => false);
    }
  }

  // Helper function to ensure image URL is valid
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

  // Group posts by trip
  List<Map<String, dynamic>> _groupPostsByTrip(List<dynamic> posts) {
    Map<String, Map<String, dynamic>> tripGroups = {};

    for (var post in posts) {
      if (post is Map) {
        String tripKey = 'unknown';
        String tripName = 'Unknown Trip';
        int? tripId;

        if (post['trip'] != null && post['trip'] is Map) {
          tripId = post['trip']['id'];
          tripName = post['trip']['destination'] ?? 'Unknown Trip';
          tripKey = 'trip_$tripId';
        } else if (post['trip_id'] != null) {
          tripId = post['trip_id'];
          tripKey = 'trip_$tripId';
        } else if (post['trip_display'] != null) {
          tripName = post['trip_display'].toString();
          tripKey = tripName;
        } else if (post['destination'] != null) {
          tripName = post['destination'].toString();
          tripKey = tripName;
        }

        String imageUrl = '';
        if (post['display_image_url'] != null) {
          imageUrl = post['display_image_url'].toString();
        } else if (post['image_url'] != null) {
          imageUrl = _getValidImageUrl(post['image_url']);
        } else if (post['url'] != null) {
          imageUrl = _getValidImageUrl(post['url']);
        }

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

  Future<void> fetchProfileData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    try {
      // Basic profile info
      final profileRes = await http.get(
        Uri.parse('$baseUrl/api/profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (profileRes.statusCode == 200) {
        final data = jsonDecode(profileRes.body);
        final userId = data['id'];

        final otherRes = await http.get(
          Uri.parse('$baseUrl/api/profile/$userId/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Token $token',
          },
        );

        if (otherRes.statusCode == 200) {
          final other = jsonDecode(otherRes.body);

          // Process posts to extract trip information
          final processedPosts = (other['posts'] as List).map((post) {
            if (post is Map) {
              String imageUrl = '';

              if (post['image_url'] != null) {
                imageUrl = post['image_url'].toString();
              } else if (post['url'] != null) {
                imageUrl = post['url'].toString();
              } else if (post['image'] != null) {
                imageUrl = post['image'].toString();
              }

              final validUrl = _getValidImageUrl(imageUrl);

              String tripDestination = 'Unknown Trip';
              String tripDate = '';
              Map<String, dynamic>? tripDetails;
              int? tripId;

              if (post['trip'] != null) {
                if (post['trip'] is Map) {
                  tripDetails = Map<String, dynamic>.from(post['trip']);
                  if (tripDetails['destination'] != null) {
                    tripDestination = tripDetails['destination'].toString();
                  }
                  if (tripDetails['id'] != null) {
                    tripId = tripDetails['id'];
                  }
                  if (tripDetails['start_date'] != null) {
                    tripDate = ' • ${tripDetails['start_date']}';
                  }
                } else if (post['trip'] is String) {
                  tripId = int.tryParse(post['trip'].toString());
                } else if (post['trip'] is num) {
                  tripId = (post['trip'] as num).toInt();
                }
              }

              if (tripDestination == 'Unknown Trip' && post['trip_destination'] != null) {
                tripDestination = post['trip_destination'].toString();
              }
              if (tripDestination == 'Unknown Trip' && post['destination'] != null) {
                tripDestination = post['destination'].toString();
              }
              if (tripDestination == 'Unknown Trip' && post['trip_details'] != null) {
                if (post['trip_details'] is Map) {
                  tripDetails = Map<String, dynamic>.from(post['trip_details']);
                  if (tripDetails['destination'] != null) {
                    tripDestination = tripDetails['destination'].toString();
                  }
                  if (tripDetails['id'] != null) {
                    tripId = tripDetails['id'];
                  }
                }
              }
              if (tripDestination == 'Unknown Trip' && post['trip'] != null && post['trip'] is Map) {
                var tripMap = post['trip'] as Map;
                if (tripMap['destination'] != null) {
                  tripDestination = tripMap['destination'].toString();
                }
              }
              if (tripDestination == 'Unknown Trip') {
                if (post['trip_name'] != null) {
                  tripDestination = post['trip_name'].toString();
                } else if (post['trip_title'] != null) {
                  tripDestination = post['trip_title'].toString();
                } else if (post['location'] != null) {
                  tripDestination = post['location'].toString();
                } else if (post['place'] != null) {
                  tripDestination = post['place'].toString();
                }
              }

              return {
                ...post,
                'id': post['id'],
                'display_image_url': validUrl,
                'image_url': validUrl,
                'trip_display': tripDestination,
                'trip_date': tripDate,
                'trip_id': tripId,
                'trip_details': tripDetails ?? post['trip'] ?? post['trip_details'],
              };
            }
            return post;
          }).toList();

          final grouped = _groupPostsByTrip(processedPosts);

          setState(() {
            username = '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'.trim();
            if (username.isEmpty) username = 'Unknown';
            email = data['email'] ?? 'No email';
            bio = data['bio'] ?? '';
            profilePicture = data['profile_picture'];
            postCount = processedPosts.length;
            tripCount = other['trip_count'] ?? 0;
            followerCount = other['follower_count'] ?? 0;
            followingCount = other['following_count'] ?? 0;
            trips = other['trips'] ?? [];
            groupedPosts = grouped;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    await fetchProfileData();
  }

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.login, (route) => false);
    }
  }

  // ── NEW: UPDATE BIO IN BACKEND ───────────────────────────────────────────────
  Future<void> _updateBio(String newBio) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    try {
      await http.patch(
        Uri.parse('$baseUrl/api/profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({"bio": newBio}),
      );
      debugPrint("Bio updated successfully to backend.");
    } catch (e) {
      debugPrint('Error updating bio: $e');
    }
  }

  Future<void> _uploadProfilePicture(File imageFile) async {
    final supabase = Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    final fileName = 'profile-${DateTime.now().millisecondsSinceEpoch}.png';
    final path = 'profile-pictures/$fileName';

    try {
      await supabase.storage.from('profile-pictures').uploadBinary(
        path,
        await imageFile.readAsBytes(),
        fileOptions: const FileOptions(contentType: 'image/png'),
      );

      final url = supabase.storage.from('profile-pictures').getPublicUrl(path);

      final updateRes = await http.patch(
        Uri.parse('$baseUrl/api/profile/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({"profile_picture": url}),
      );

      if (updateRes.statusCode == 200) {
        setState(() => profilePicture = url);
      } else {
        debugPrint('Failed to update profile picture: ${updateRes.body}');
      }
    } catch (e) {
      debugPrint('Error uploading profile picture: $e');
    }
  }

  // ── ALBUM VIEWER & DELETION ───────────────────────────────────────────────

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
                                icon: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                                onPressed: () => _confirmDeleteAlbum(tripAlbum),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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

  void _confirmDeleteAlbum(Map<String, dynamic> album) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album'),
        content: Text(
          'Are you sure you want to delete all ${(album['images'] as List).length} photos from "${album['trip_name']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); 
              _deleteAlbum(album);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAlbum(Map<String, dynamic> album) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final images = album['images'] as List;
    final postIds = album['post_ids'] as List;

    if (postIds.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      for (var postId in postIds) {
        try {
          await http.delete(
            Uri.parse('$baseUrl/api/posts/$postId/'),
            headers: {'Authorization': 'Token $token'},
          );
        } catch (e) {
          debugPrint('Error deleting post $postId: $e');
        }
      }

      for (var image in images) {
        try {
          final imageUrl = image['url'] as String;
          final Uri uri = Uri.parse(imageUrl);
          final path = uri.pathSegments.last;
          await Supabase.instance.client.storage.from('post-image').remove([path]);
        } catch (e) {
          debugPrint('Error deleting image from Supabase: $e');
        }
      }

      await fetchProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${images.length} photos deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting album: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── DIALOGS ───────────────────────────────────────────────────────────────

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _logout(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), onTap: () {}),
            ListTile(leading: const Icon(Icons.tune), title: const Text('Account Preferences'), onTap: () {}),
            ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Privacy'), onTap: () {}),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _showLogoutDialog(); },
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.black))
            : RefreshIndicator(
                onRefresh: _refresh,
                color: Colors.black,
                child: CustomScrollView(
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Center(
                              child: Text(
                                'Profile',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: _showSettingsMenu,
                                child: const _CompassSettingsIcon(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 10)),

                    // Avatar + info
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
                                    username,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    email,
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
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

                    // Edit Profile Button (NOW UPDATED WITH BIO PATCH)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditProfilePage(
                                    username: username,
                                    currentBio: bio,
                                    currentProfilePicture: profilePicture,
                                  ),
                                ),
                              );

                              if (result != null) {
                                // 1. Update Bio
                                final newBio = result["bio"];
                                if (newBio != null && newBio != bio) {
                                  setState(() {
                                    bio = newBio;
                                  });
                                  _updateBio(newBio); // Send to Backend
                                }

                                // 2. Update Image
                                final File? imageFile = result["image"];
                                if (imageFile != null) {
                                  await _uploadProfilePicture(imageFile);
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Edit Profile',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    // Stats
                    SliverToBoxAdapter(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(postCount.toString(), 'Posts'),
                          _StatItem(tripCount.toString(), 'Trips'),
                          _StatItem(followerCount.toString(), 'Followers'),
                          _StatItem(followingCount.toString(), 'Following'),
                        ],
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    // Tabs Header
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

                    // Tab Content (SliverFillRemaining prevents overflow/fixed height issues)
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
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          backgroundColor: Colors.black,
                                          child: Icon(Icons.location_on, color: Colors.white, size: 18),
                                        ),
                                        title: Text(
                                          trip['destination'] ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(trip['start_date']?.toString() ?? ''),
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
                                    final firstImage = album['first_image'] ??
                                        (images.isNotEmpty ? images[0]['url'] : '');
                                    final imageCount = images.length;
                                    final tripName = album['trip_name'] ?? 'Unknown Trip';

                                    return GestureDetector(
                                      onTap: () => _showTripAlbum(album),
                                      onLongPress: () => _confirmDeleteAlbum(album),
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
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withOpacity(0.7),
                                                  ],
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

// ── HELPER WIDGETS ────────────────────────────────────────────────────────────

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

class _CompassSettingsIcon extends StatelessWidget {
  const _CompassSettingsIcon();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.settings,   size: 26, color: Colors.black),
        Icon(Icons.navigation, size: 14, color: Colors.black),
      ],
    );
  }
}

class TripCard extends StatelessWidget {
  final String title;
  final String status;
  const TripCard({Key? key, required this.title, required this.status})
      : super(key: key);

  Color _statusColor() {
    switch (status) {
      case 'Ongoing':   return Colors.orange;
      case 'Upcoming':  return Colors.blue;
      case 'Completed': return Colors.green;
      default:          return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: const Icon(Icons.location_on, color: Colors.black),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor().withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(status,
              style: TextStyle(color: _statusColor(), fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}