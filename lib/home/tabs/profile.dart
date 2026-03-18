import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import '../../routes.dart';
import 'package:flutter_app/config/config.dart';
import '../profile/edit_profile.dart';
import '../profile/other_profile.dart';

const String baseUrl = AppConfig.baseUrl;

class UserProfile extends StatefulWidget {
  const UserProfile({Key? key}) : super(key: key);

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String  username       = 'Loading...';
  String  email          = 'Loading...';
  String  bio            = '';
  String? profilePicture;
  int     postCount      = 0;
  int     tripCount      = 0;
  int     followerCount  = 0;
  int     followingCount = 0;
  List    trips          = [];
  List<Map<String, dynamic>> groupedPosts = [];
  bool    _isLoading     = true;
  int?    _currentUserId;

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

  // ── Auth & Data ───────────────────────────────────────────────────────────

  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null && mounted) {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.login, (route) => false);
    }
  }

  String _getValidImageUrl(dynamic imageUrl) {
    if (imageUrl == null) return '';
    String url = imageUrl.toString().trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;

    try {
      final supabase = Supabase.instance.client;
      return supabase.storage.from('post-image').getPublicUrl(url);
    } catch (e) {
      debugPrint('Error constructing image URL: $e');
      return url;
    }
  }

  List<Map<String, dynamic>> _groupPostsByTrip(List<dynamic> posts) {
    Map<String, Map<String, dynamic>> tripGroups = {};

    for (var post in posts) {
      if (post is Map) {
        String tripKey  = 'unknown';
        String tripName = 'Unknown Trip';
        int?   tripId;

        if (post['trip'] != null && post['trip'] is Map) {
          tripId   = post['trip']['id'];
          tripName = post['trip']['destination'] ?? 'Unknown Trip';
          tripKey  = 'trip_$tripId';
        } else if (post['trip_id'] != null) {
          tripId  = post['trip_id'];
          tripKey = 'trip_$tripId';
        } else if (post['trip_display'] != null) {
          tripName = post['trip_display'].toString();
          tripKey  = tripName;
        } else if (post['destination'] != null) {
          tripName = post['destination'].toString();
          tripKey  = tripName;
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
            'trip_id':      tripId,
            'trip_name':    tripName,
            'images':       [],
            'first_image':  imageUrl,
            'post_ids':     [],
            'trip_details': post['trip_details'] ?? post['trip'],
          };
        }

        if (imageUrl.isNotEmpty) {
          tripGroups[tripKey]!['images'].add({
            'url':     imageUrl,
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
      final profileRes = await http.get(
        Uri.parse('$baseUrl/api/profile/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (profileRes.statusCode == 200) {
        final data   = jsonDecode(profileRes.body);
        final userId = data['id'];
        setState(() => _currentUserId = userId);

        final tripsRes = await http.get(
          Uri.parse('$baseUrl/api/savetrip/my-trips/'),
          headers: {
            'Content-Type':  'application/json',
            'Authorization': 'Token $token',
          },
        );

        final otherRes = await http.get(
          Uri.parse('$baseUrl/api/profile/$userId/'),
          headers: {
            'Content-Type':  'application/json',
            'Authorization': 'Token $token',
          },
        );

        List tripsData = [];
        if (tripsRes.statusCode == 200) {
          tripsData = jsonDecode(tripsRes.body);
        }

        if (otherRes.statusCode == 200) {
          final other = jsonDecode(otherRes.body);

          final processedPosts = (other['posts'] as List).map((post) {
            if (post is Map) {
              String imageUrl = post['image_url']?.toString() ??
                  post['url']?.toString() ??
                  post['image']?.toString() ?? '';
              final validUrl = _getValidImageUrl(imageUrl);

              String tripDestination = 'Unknown Trip';
              String tripDate        = '';
              Map<String, dynamic>? tripDetails;
              int?   tripId;

              if (post['trip'] != null) {
                if (post['trip'] is Map) {
                  tripDetails = Map<String, dynamic>.from(post['trip']);
                  if (tripDetails['destination'] != null) {
                    tripDestination = tripDetails['destination'].toString();
                  }
                  if (tripDetails['id'] != null) tripId = tripDetails['id'];
                  if (tripDetails['start_date'] != null) {
                    tripDate = ' • ${tripDetails['start_date']}';
                  }
                } else if (post['trip'] is String) {
                  tripId = int.tryParse(post['trip'].toString());
                } else if (post['trip'] is num) {
                  tripId = (post['trip'] as num).toInt();
                }
              }

              if (tripDestination == 'Unknown Trip' &&
                  post['trip_destination'] != null) {
                tripDestination = post['trip_destination'].toString();
              }
              if (tripDestination == 'Unknown Trip' &&
                  post['destination'] != null) {
                tripDestination = post['destination'].toString();
              }

              return {
                ...post,
                'id':               post['id'],
                'display_image_url': validUrl,
                'image_url':        validUrl,
                'trip_display':     tripDestination,
                'trip_date':        tripDate,
                'trip_id':          tripId,
                'trip_details':
                    tripDetails ?? post['trip'] ?? post['trip_details'],
              };
            }
            return post;
          }).toList();

          final grouped = _groupPostsByTrip(processedPosts);

          setState(() {
            username = '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'
                .trim();
            if (username.isEmpty) username = 'Unknown';
            email          = data['email'] ?? 'No email';
            bio            = data['bio'] ?? '';
            profilePicture = data['profile_picture'];
            postCount      = processedPosts.length;
            tripCount      = tripsData.length;
            followerCount  = other['follower_count']  ?? 0;
            followingCount = other['following_count'] ?? 0;
            trips          = tripsData;
            groupedPosts   = grouped;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async => fetchProfileData();

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

  // ── Followers / Following ─────────────────────────────────────────────────

  Future<void> _showFollowersList() async {
    if (_currentUserId == null) return;
    await _fetchAndShowUsers('followers', 'Followers');
  }

  Future<void> _showFollowingList() async {
    if (_currentUserId == null) return;
    await _fetchAndShowUsers('following', 'Following');
  }

  Future<void> _fetchAndShowUsers(String type, String title) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: Colors.black)),
    );

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/profile/$_currentUserId/$type/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (context.mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final List<dynamic> users = jsonDecode(response.body);
        if (context.mounted) _showUserBottomSheet(title, users);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to load $title'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      debugPrint('Error fetching $type: $e');
    }
  }

  void _showUserBottomSheet(String title, List<dynamic> users) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              title == 'Followers'
                                  ? Icons.people_outline
                                  : Icons.person_outline,
                              size: 48,
                              color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                              title == 'Followers'
                                  ? 'No followers yet'
                                  : 'Not following anyone',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: user['profile_picture'] !=
                                        null &&
                                    user['profile_picture']
                                        .toString()
                                        .isNotEmpty
                                ? NetworkImage(user['profile_picture'])
                                : null,
                            child: user['profile_picture'] == null ||
                                    user['profile_picture']
                                        .toString()
                                        .isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.grey)
                                : null,
                          ),
                          title: Text(user['username'] ?? 'Unknown User',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(user['email'] ?? '',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => OtherUserProfilePage(
                                  userId:   user['id'],
                                  userName: user['username'] ?? 'User',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Trip Card ─────────────────────────────────────────────────────────────

  Widget _buildTripCard(Map trip) {
    final tripStatus = (trip['status'] as String? ?? 'upcoming').toLowerCase();
    final isAdmin    = trip['is_admin'] == true;

    int tripId = 0;
    if (trip['trip_id'] is int)       tripId = trip['trip_id'];
    else if (trip['id'] is int)       tripId = trip['id'];
    else if (trip['trip_id'] != null) tripId = int.tryParse(trip['trip_id'].toString()) ?? 0;
    else if (trip['id'] != null)      tripId = int.tryParse(trip['id'].toString()) ?? 0;

    Color    statusColor;
    String   statusLabel;
    IconData statusIcon;

    switch (tripStatus) {
      case 'ongoing':
        statusColor = Colors.orange;
        statusLabel = 'Ongoing';
        statusIcon  = Icons.directions_run;
        break;
      case 'completed':
        statusColor = Colors.green;
        statusLabel = 'Completed';
        statusIcon  = Icons.check_circle;
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = 'Upcoming';
        statusIcon  = Icons.calendar_today;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 0,
      color: const Color(0xFFF9F9F9),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          if (tripStatus == 'upcoming') {
            // FIX: ...trip caused "Map<dynamic,dynamic> is not a subtype" crash
            // because trip is typed as Map (not Map<String,dynamic>).
            // Spread it safely by casting first.
            final safeTrip = Map<String, dynamic>.from(trip);
            Navigator.pushNamed(
              context,
              AppRoutes.groupChat,
              arguments: {
                ...safeTrip,
                'group_id':   trip['group_id'] ?? 0,
                'group_name': (trip['group_name'] ?? trip['destination'] ?? 'Group').toString(),
                'admin_id':   trip['admin_id'] ?? 0,
                'trip_id':    tripId,
              },
            );
          } else if (tripStatus == 'ongoing') {
            if (tripId == 0) return;
            if (isAdmin) {
              Navigator.pushNamed(
                context,
                AppRoutes.otpVerify,
                arguments: {
                  'trip_id':   tripId,
                  'trip_name': (trip['destination'] ?? 'Trip').toString(),
                },
              );
            } else {
              Navigator.pushNamed(
                context,
                AppRoutes.otpShow,
                arguments: {
                  'trip_id':   tripId,
                  'trip_name': (trip['destination'] ?? 'Trip').toString(),
                },
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withOpacity(0.15),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip['destination']?.toString() ?? 'Unknown',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trip['start_date']?.toString() ??
                          trip['date']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: statusColor.withOpacity(0.4), width: 1),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              if (tripStatus != 'completed') ...[
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.grey[400]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Bio & Profile Pic update ──────────────────────────────────────────────

  Future<void> _updateBio(String newBio) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    try {
      await http.patch(
        Uri.parse('$baseUrl/api/profile/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({'bio': newBio}),
      );
    } catch (e) {
      debugPrint('Error updating bio: $e');
    }
  }

  Future<void> _uploadProfilePicture(File imageFile) async {
    final supabase = Supabase.instance.client;
    final prefs    = await SharedPreferences.getInstance();
    final token    = prefs.getString('auth_token');
    if (token == null) return;

    final fileName = 'profile-${DateTime.now().millisecondsSinceEpoch}.png';
    final path     = 'profile-pictures/$fileName';

    try {
      await supabase.storage.from('profile-pictures').uploadBinary(
            path,
            await imageFile.readAsBytes(),
            fileOptions: const FileOptions(contentType: 'image/png'),
          );

      final url =
          supabase.storage.from('profile-pictures').getPublicUrl(path);

      final updateRes = await http.patch(
        Uri.parse('$baseUrl/api/profile/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({'profile_picture': url}),
      );

      if (updateRes.statusCode == 200) {
        setState(() => profilePicture = url);
      }
    } catch (e) {
      debugPrint('Error uploading profile picture: $e');
    }
  }

  // ── Album viewer ──────────────────────────────────────────────────────────

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
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.black.withOpacity(0.7)),
                  ),
                ),
                Positioned.fill(
                    child: Container(color: Colors.black.withOpacity(0.3))),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.transparent),
                ),
                Column(
                  children: [
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on,
                                        color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tripAlbum['trip_name']
                                                    ?.toString() ??
                                                'Unknown',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${images.length} ${images.length == 1 ? 'photo' : 'photos'}',
                                            style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.8),
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _albumIconBtn(Icons.delete_outline,
                                () => _confirmDeleteAlbum(tripAlbum)),
                            const SizedBox(width: 8),
                            _albumIconBtn(
                                Icons.close, () => Navigator.pop(context)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        itemCount: images.length,
                        controller: PageController(initialPage: currentIndex),
                        onPageChanged: (index) =>
                            setState(() => currentIndex = index),
                        itemBuilder: (_, index) {
                          return InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.network(
                                images[index]['url'],
                                fit: BoxFit.contain,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress
                                                  .expectedTotalBytes !=
                                              null
                                          ? loadingProgress
                                                  .cumulativeBytesLoaded /
                                              loadingProgress
                                                  .expectedTotalBytes!
                                          : null,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image,
                                        color: Colors.white.withOpacity(0.7),
                                        size: 50),
                                    const SizedBox(height: 8),
                                    Text('Failed to load image',
                                        style: TextStyle(
                                            color: Colors.white
                                                .withOpacity(0.7))),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (images.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1),
                                ),
                                child: Text(
                                  '${currentIndex + 1} / ${images.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500),
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

  Widget _albumIconBtn(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 22),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
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
              child: const Text('Cancel')),
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
    final prefs   = await SharedPreferences.getInstance();
    final token   = prefs.getString('auth_token');
    final images  = album['images'] as List;
    final postIds = album['post_ids'] as List;

    if (postIds.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // Delete posts from backend
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

      // Delete images from Supabase storage
      // FIX: extract the full storage object path, not just the filename.
      // A public URL looks like:
      //   https://<project>.supabase.co/storage/v1/object/public/post-image/<path>
      // We need everything after "/post-image/" as the storage object path.
      for (var image in images) {
        try {
          final imageUrl = image['url'] as String;
          final uri      = Uri.parse(imageUrl);

          // Find the bucket name segment and take everything after it
          final segments   = uri.pathSegments;
          final bucketName = 'post-image';
          final bucketIdx  = segments.indexOf(bucketName);

          if (bucketIdx != -1 && bucketIdx < segments.length - 1) {
            // Reconstruct the path inside the bucket
            final storagePath =
                segments.sublist(bucketIdx + 1).join('/');
            await Supabase.instance.client.storage
                .from(bucketName)
                .remove([storagePath]);
          }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error deleting photos: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
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
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10)),
            ),
            ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () => Navigator.pop(context)),
            ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Account Preferences'),
                onTap: () => Navigator.pop(context)),
            ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Privacy'),
                onTap: () => Navigator.pop(context)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showLogoutDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.black))
            : RefreshIndicator(
                onRefresh: _refresh,
                color: Colors.black,
                child: CustomScrollView(
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Center(
                              child: Text(
                                'Profile',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.grey),
                                  ),
                                  if (bio.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      bio,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black87),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 15),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.black, width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor:
                                    const Color(0xFFF5F5F5),
                                backgroundImage: profilePicture != null &&
                                        profilePicture!.isNotEmpty
                                    ? NetworkImage(profilePicture!)
                                    : null,
                                child: profilePicture == null ||
                                        profilePicture!.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 40, color: Colors.grey)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    // Edit Profile button
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
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
                                final newBio = result['bio'];
                                if (newBio != null && newBio != bio) {
                                  setState(() => bio = newBio);
                                  _updateBio(newBio);
                                }
                                final File? imageFile = result['image'];
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
                                style: TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    // Stats
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                                child: _StatItem(
                                    postCount.toString(), 'Posts')),
                            Expanded(
                                child: _StatItem(
                                    tripCount.toString(), 'Trips')),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _showFollowersList,
                                  borderRadius: BorderRadius.circular(10),
                                  splashColor:
                                      Colors.black.withOpacity(0.1),
                                  highlightColor: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8),
                                    child: _StatItem(
                                        followerCount.toString(),
                                        'Followers'),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _showFollowingList,
                                  borderRadius: BorderRadius.circular(10),
                                  splashColor:
                                      Colors.black.withOpacity(0.1),
                                  highlightColor: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8),
                                    child: _StatItem(
                                        followingCount.toString(),
                                        'Following'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 15)),

                    // Tabs
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

                    // Tab content
                    SliverFillRemaining(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Trips tab
                          trips.isEmpty
                              ? Center(
                                  child: _emptyState(
                                      Icons.luggage, 'No trips yet'))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: trips.length,
                                  itemBuilder: (context, index) {
                                    return _buildTripCard(
                                        trips[index] as Map);
                                  },
                                ),

                          // Posts (Albums) tab
                          groupedPosts.isEmpty
                              ? Center(
                                  child: _emptyState(Icons.photo_library,
                                      'No posts yet'))
                              : GridView.builder(
                                  padding: const EdgeInsets.all(10),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 5,
                                    mainAxisSpacing: 5,
                                  ),
                                  itemCount: groupedPosts.length,
                                  itemBuilder: (context, index) {
                                    final album      = groupedPosts[index];
                                    final images     = album['images'] as List;
                                    final firstImage = album['first_image'] ??
                                        (images.isNotEmpty
                                            ? images[0]['url']
                                            : '');
                                    final imageCount = images.length;
                                    final tripName   =
                                        album['trip_name'] ?? 'Unknown Trip';

                                    return GestureDetector(
                                      onTap: () => _showTripAlbum(album),
                                      onLongPress: () =>
                                          _confirmDeleteAlbum(album),
                                      child: Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: firstImage.isEmpty
                                                ? Container(
                                                    color: Colors.grey[200],
                                                    child: const Center(
                                                        child: Icon(
                                                            Icons.broken_image,
                                                            color:
                                                                Colors.grey)),
                                                  )
                                                : Image.network(
                                                    firstImage,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    loadingBuilder: (context,
                                                        child,
                                                        loadingProgress) {
                                                      if (loadingProgress ==
                                                          null) return child;
                                                      return Container(
                                                        color:
                                                            Colors.grey[200],
                                                        child: Center(
                                                          child:
                                                              CircularProgressIndicator(
                                                            value: loadingProgress
                                                                        .expectedTotalBytes !=
                                                                    null
                                                                ? loadingProgress
                                                                        .cumulativeBytesLoaded /
                                                                    loadingProgress
                                                                        .expectedTotalBytes!
                                                                : null,
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.black,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
                                                      return Container(
                                                        color:
                                                            Colors.grey[200],
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .broken_image,
                                                                color: Colors
                                                                    .grey,
                                                                size: 30),
                                                            const SizedBox(
                                                                height: 4),
                                                            Text('Error',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    color: Colors
                                                                        .grey[600])),
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
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withOpacity(0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                        Icons.folder_copy,
                                                        color: Colors.white,
                                                        size: 12),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '$imageCount',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    const BorderRadius.only(
                                                  bottomLeft:
                                                      Radius.circular(10),
                                                  bottomRight:
                                                      Radius.circular(10),
                                                ),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black
                                                        .withOpacity(0.7),
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
                                                overflow:
                                                    TextOverflow.ellipsis,
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
        Text(message,
            style: const TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
          textAlign: TextAlign.center,
        ),
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
        Icon(Icons.settings, size: 26, color: Colors.black),
        Icon(Icons.navigation, size: 14, color: Colors.black),
      ],
    );
  }
}