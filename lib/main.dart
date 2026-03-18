import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'routes.dart';
import 'theme/app_theme.dart';
import 'home/profile/other_profile.dart';
import 'home/tabs/groups/group_details.dart';
import 'otp/otp_verify.dart';
import 'otp/otp_show.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url:     'https://tqmrytzypqsuxjwdrihh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
             '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRxbXJ5dHp5cHFzdXhqd2RyaWhoIiwi'
             'cm9sZSI6ImFub24iLCJpYXQiOjE3NzI5Mzk0MjIsImV4cCI6MjA4ODUxNTQyMn0'
             '.SXDr2pA7Bt1fPy9Tg14nhCF0oGz9hQJe1G4_8nA-5tU',
  );

  final prefs         = await SharedPreferences.getInstance();
  final String? token = prefs.getString('auth_token');
  final String initialRoute = token != null ? AppRoutes.home : AppRoutes.login;

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SeeMe',
      theme: AppTheme.lightTheme,
      initialRoute: initialRoute,
      routes:       AppRoutes.routes,

      onGenerateRoute: (settings) {
        // ── Other user profile ───────────────────────────────────────────
        if (settings.name == AppRoutes.otherProfile) {
          final args = (settings.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final userId = args['user_id'] is int
              ? args['user_id'] as int
              : int.tryParse(args['user_id']?.toString() ?? '') ?? 0;
          final userName = args['user_name']?.toString() ?? 'User';

          return MaterialPageRoute(
            builder: (_) => OtherUserProfilePage(
              userId:   userId,
              userName: userName,
            ),
          );
        }

        // ── Group details ────────────────────────────────────────────────
        if (settings.name == AppRoutes.groupDetails) {
          final args = (settings.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final groupId = args['group_id'] is int
              ? args['group_id'] as int
              : int.tryParse(args['group_id']?.toString() ?? '') ?? 0;
          final adminId = args['admin_id'] is int
              ? args['admin_id'] as int
              : int.tryParse(args['admin_id']?.toString() ?? '') ?? 0;
          final groupName = args['group_name']?.toString() ?? 'Group';

          return MaterialPageRoute(
            builder: (_) => GroupDetailsPage(
              groupId:   groupId,
              groupName: groupName,
              adminId:   adminId,
            ),
          );
        }

        // ── OTP Verify (admin boarding page) ────────────────────────────
        if (settings.name == AppRoutes.otpVerify) {
          final args = (settings.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final tripId = args['trip_id'] is int
              ? args['trip_id'] as int
              : int.tryParse(args['trip_id']?.toString() ?? '') ?? 0;
          final tripName = args['trip_name']?.toString() ?? 'Trip';

          return MaterialPageRoute(
            builder: (_) => OtpVerifyPage(
              tripId:   tripId,
              tripName: tripName,
            ),
          );
        }

        // ── OTP Show (member boarding page) ─────────────────────────────
        if (settings.name == AppRoutes.otpShow) {
          final args = (settings.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final tripId = args['trip_id'] is int
              ? args['trip_id'] as int
              : int.tryParse(args['trip_id']?.toString() ?? '') ?? 0;
          final tripName = args['trip_name']?.toString() ?? 'Trip';

          return MaterialPageRoute(
            builder: (_) => OtpShowPage(
              tripId:   tripId,
              tripName: tripName,
            ),
          );
        }

        return null;
      },
    );
  }
}