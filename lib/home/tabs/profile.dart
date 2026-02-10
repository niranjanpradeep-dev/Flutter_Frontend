import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../routes.dart';
import 'package:flutter_app/config/config.dart';


// UPDATED IP: Ensure this matches your computer's current IP (checked via ipconfig)
const String baseUrl = AppConfig.baseUrl;

class UserProfile extends StatefulWidget {
  const UserProfile({super.key});

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile> {
  // Variables to hold profile data
  String username = "Loading...";
  String email = "Loading..."; // Added variable for email
  String bio = "Loading...";
  String postCount = "-";
  
  @override
  void initState() {
    super.initState();
    fetchProfileData();
  }

  Future<void> fetchProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('auth_token');

    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/profile/"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Token $token",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          // Parse data from server
          username = data['first_name'] + " " + data['last_name'] ?? "Unknown";
          email = data['email'] ?? "No email"; // Get email from response
          bio = data['bio'] ?? "No bio yet.";
          postCount = data['post_count'].toString();
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  // --- LOGOUT FUNCTION ---
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token'); // Clear the key
    
    if (mounted) {
      // Navigate to Login and remove all previous routes so back button doesn't work
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(username), 
        actions: [
          // --- LOGOUT BUTTON ---
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red), // Red logout icon
            onPressed: logout,
            tooltip: "Log Out",
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.grey[300],
                            child: const Icon(Icons.person, size: 40, color: Colors.white),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _StatItem(postCount, "Submitted"),
                                const _StatItem("1.6k", "Subscribe"),
                                const _StatItem("380", "Connect"),
                              ],
                            ),
                          )
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // --- UPDATED NAME & EMAIL SECTION ---
                      Text(
                        username, // Display Name
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        email, // Display Email
                        style: const TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      
                      Text(
                        bio, // Display Bio
                        style: const TextStyle(color: Colors.grey),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6F35A5),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: const Text("Edit Profile"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Share Profile"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: Column(
            children: [
              const TabBar(
                indicatorColor: Colors.black,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  Tab(icon: Icon(CupertinoIcons.square_grid_2x2)),
                  Tab(icon: Icon(CupertinoIcons.person_crop_square)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    GridView.builder(
                      padding: const EdgeInsets.all(1),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, crossAxisSpacing: 1, mainAxisSpacing: 1,
                      ),
                      itemCount: 15,
                      itemBuilder: (context, index) => Container(
                        color: Colors.grey[300],
                        child: Icon(Icons.image, color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                    const Center(child: Text("Tagged posts appear here")),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  const _StatItem(this.count, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(count, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}