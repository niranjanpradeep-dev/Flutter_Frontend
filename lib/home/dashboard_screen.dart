import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// Import your tabs
import 'tabs/feed/feed.dart';
import 'tabs/join/search.dart';
import 'tabs/profile.dart';
import 'tabs/groups/group_list.dart'; // <--- Import the GroupList page

// Import the Trip Details page (for the + button)
import 'tabs/trip/trip_details.dart'; 

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomeFeed(),                  // 0: Home
    SearchGrid(),                // 1: Explore
    SizedBox(),                  // 2: Placeholder for the (+) button logic
    GroupListPage(),             // 3: Journey (Replaced Placeholder)
    UserProfile(),               // 4: Profile
  ];

  void _onItemTapped(int index) {
    // If the middle "+" button is tapped
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TripDetailsPage()),
      );
      return; // Stop here so we don't switch the tab index
    }
    
    // Otherwise, switch the tab
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFF0F0F0), width: 1),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            selectedItemColor: Colors.black,
            unselectedItemColor: Colors.grey,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
            items: [
              const BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(CupertinoIcons.house_fill, size: 26),
                ),
                label: 'Home',
              ),
              const BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(CupertinoIcons.compass, size: 28),
                ),
                label: 'Explore',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 48,
                  width: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC107), // Your Theme Yellow
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.add,
                    color: Colors.black87,
                    size: 28,
                  ),
                ),
                label: '',
              ),
              const BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(CupertinoIcons.chat_bubble, size: 26),
                ),
                label: 'Journey',
              ),
              const BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Icon(CupertinoIcons.person, size: 26),
                ),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}