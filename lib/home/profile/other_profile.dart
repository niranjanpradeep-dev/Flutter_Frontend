import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_app/config/config.dart';
import '../../routes.dart';

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
  int?   _currentUserId;

  String  name           = '';
  String  bio            = '';
  String? profilePicture;
  int     postCount      = 0;
  int     tripCount      = 0;
  int     followerCount  = 0;
  int     followingCount = 0;
  List    posts          = [];
  List    trips          = [];
  List<Map<String, dynamic>> groupedPosts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _getCurrentUserId().then((id) {
      setState(() => _currentUserId = id);
      _loadProfile();
    });
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

  Future<int?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/profile/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id'];
      }
    } catch (e) {
      debugPrint('Error getting user ID: $e');
    }
    return null;
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

  List<Map<String, dynamic>> _groupPostsByTrip(List<dynamic> postsList) {
    Map<String, Map<String, dynamic>> tripGroups = {};

    for (var post in postsList) {
      if (post is Map) {
        String tripKey  = 'unknown';
        String tripName = post['trip_display']?.toString() ?? 'Unknown Trip';
        int?   tripId;

        if (post['trip'] != null && post['trip'] is Map) {
          tripId   = post['trip']['id'];
          tripName = post['trip']['destination']?.toString() ?? tripName;
          tripKey  = 'trip_$tripId';
        } else if (post['trip_id'] != null) {
          tripId  = post['trip_id'];
          tripKey = 'trip_$tripId';
        } else if (post['trip_display'] != null) {
          tripKey = tripName;
        } else if (post['destination'] != null) {
          tripName = post['destination'].toString();
          tripKey  = tripName;
        }

        String imageUrl = post['display_image_url']?.toString() ??
            _getValidImageUrl(post['image_url']);

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

  Future<void> _loadProfile() async {
    if (posts.isEmpty) setState(() => _isLoading = true);

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
        final data     = jsonDecode(response.body);
        final rawPosts = data['posts'] ?? [];

        final processedPosts = (rawPosts as List).map((post) {
          if (post is Map) {
            String imageUrl = post['image_url']?.toString() ??
                post['url']?.toString() ??
                post['image']?.toString() ?? '';
            final validUrl = _getValidImageUrl(imageUrl);

            String tripDestination = 'Unknown Trip';
            int?   tripId;
            Map<String, dynamic>? tripDetails;

            if (post['trip'] != null) {
              if (post['trip'] is Map) {
                tripDetails = Map<String, dynamic>.from(post['trip']);
                if (tripDetails['destination'] != null) {
                  tripDestination = tripDetails['destination'].toString();
                }
                if (tripDetails['id'] != null) tripId = tripDetails['id'];
              }
            }

            if (tripDestination == 'Unknown Trip' && post['trip_destination'] != null) {
              tripDestination = post['trip_destination'].toString();
            }
            if (tripDestination == 'Unknown Trip' && post['destination'] != null) {
              tripDestination = post['destination'].toString();
            }

            return {
              ...Map<String, dynamic>.from(post),
              'display_image_url': validUrl,
              'trip_display':      tripDestination,
              'trip_id':           tripId,
              'trip_details':      tripDetails ?? post['trip'],
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
          followerCount  = data['follower_count']  ?? 0;
          followingCount = data['following_count'] ?? 0;
          posts          = rawPosts;
          trips          = data['trips'] ?? [];
          groupedPosts   = grouped;
          _isFollowing   = data['is_following']   ?? false;
          _isOwnProfile  = data['is_own_profile']  ?? false;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load profile: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isFollowing
                  ? 'Following ${name.isNotEmpty ? name : widget.userName}'
                  : 'Unfollowed'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Follow error: $e');
    } finally {
      if (mounted) setState(() => _followLoading = false);
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
        Uri.parse('${AppConfig.baseUrl}/api/profile/${widget.userId}/$type/'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to load $title'),
                backgroundColor: Colors.red),
          );
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

                        // Hide the current user from the list
                        if (user['id'] == _currentUserId) {
                          return const SizedBox.shrink();
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: user['profile_picture'] != null &&
                                    user['profile_picture'].toString().isNotEmpty
                                ? NetworkImage(user['profile_picture'])
                                : null,
                            child: user['profile_picture'] == null ||
                                    user['profile_picture'].toString().isEmpty
                                ? const Icon(Icons.person, color: Colors.grey)
                                : null,
                          ),
                          title: Text(user['username'] ?? 'Unknown User',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
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
            // Build a fully null-safe, String-keyed arguments map.
            // DO NOT spread the raw trip map — jsonDecode returns
            // Map<dynamic,dynamic> and any null value cast to String
            // causes "null is not a subtype of String" red screen.
            // Instead, extract every field explicitly with a fallback.
            final int tripId = trip['id'] is int
                ? trip['id'] as int
                : int.tryParse(trip['id']?.toString() ?? '') ?? 0;

            Navigator.pushNamed(
              context,
              AppRoutes.tripJoin,
              arguments: {
                'id':          tripId,
                'trip_id':     tripId,
                'destination': trip['destination']?.toString() ?? '',
                'start_date':  trip['start_date']?.toString() ?? '',
                'end_date':    trip['end_date']?.toString()   ?? '',
                'status':      trip['status']?.toString()     ?? 'upcoming',
                'vehicle':     trip['vehicle']?.toString()    ?? '',
                'passengers':  trip['passengers'] is int
                                   ? trip['passengers'] as int
                                   : int.tryParse(
                                         trip['passengers']?.toString() ?? '') ?? 0,
              },
            );
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
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              if (tripStatus == 'upcoming') ...[
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

  // ── Album Viewer ──────────────────────────────────────────────────────────

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
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white, size: 22),
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 40, minHeight: 40),
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
                onRefresh: _loadProfile,
                color: Colors.black,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.arrow_back_ios,
                                    size: 20),
                              ),
                            ),
                            Text(
                              name.isNotEmpty ? name : widget.userName,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 10)),

                    // Avatar + bio
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
                                    name.isNotEmpty ? name : widget.userName,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (bio.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(bio,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.black87)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 15),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.black, width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: const Color(0xFFF5F5F5),
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

                    // Follow button
                    if (!_isOwnProfile)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _followLoading ? null : _toggleFollow,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFollowing
                                    ? Colors.white
                                    : Colors.black,
                                foregroundColor: _isFollowing
                                    ? Colors.black
                                    : Colors.white,
                                elevation: 0,
                                side: _isFollowing
                                    ? const BorderSide(color: Colors.black)
                                    : BorderSide.none,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _followLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black))
                                  : Text(
                                      _isFollowing ? 'Following' : 'Follow',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
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
                                child:
                                    _StatItem(postCount.toString(), 'Posts')),
                            Expanded(
                                child:
                                    _StatItem(tripCount.toString(), 'Trips')),
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

                    const SliverToBoxAdapter(child: SizedBox(height: 20)),

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
                                    final tripName =
                                        album['trip_name'] ?? 'Unknown Trip';

                                    return GestureDetector(
                                      onTap: () => _showTripAlbum(album),
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
                                                                color:
                                                                    Colors.grey,
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
                                                    Text('$imageCount',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        )),
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