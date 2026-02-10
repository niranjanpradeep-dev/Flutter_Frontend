import 'package:flutter/material.dart';
import 'auth/signup.dart';
import 'auth/login.dart';
import 'home/dashboard_screen.dart';

// Import your tab/feature pages
import 'home/tabs/feed.dart';
import 'home/tabs/search.dart';
import 'home/tabs/profile.dart';
import 'home/tabs/trip/trip_details.dart';
import 'home/tabs/trip/route_details.dart';
import 'home/tabs/trip/payment_details.dart';
import 'home/tabs/trip/contact_details.dart'; // <--- Added this import

class AppRoutes {
  static const String signup = '/signup';
  static const String login = '/login';
  static const String home = '/home';
  
  // New feature routes
  static const String feed = '/feed';
  static const String search = '/search';
  static const String profile = '/profile';
  static const String tripDetails = '/trip-details';
  static const String routeDetails = '/route-details';
  static const String paymentDetails = '/payment-details';
  static const String contactDetails = '/contact-details'; // <--- Added this route name

  static Map<String, WidgetBuilder> routes = {
    signup: (context) => const SignupPage(),
    login: (context) => const LoginPage(),
    home: (context) => const DashboardScreen(),
    
    // Updated with correct class names
    feed: (context) => const HomeFeed(),         
    search: (context) => const SearchGrid(),     
    profile: (context) => const UserProfile(),    
    tripDetails: (context) => const TripDetailsPage(),
    routeDetails: (context) => const RouteDetailsPage(),
    paymentDetails: (context) => const PaymentDetailsPage(),
    contactDetails: (context) => const ContactDetailsPage(), // <--- Added this builder
  };
}