import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../routes.dart';


// Ideally, store this in a separate constants file to share between pages
const String baseUrl = "http://192.168.1.37:8000";

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _obscurePassword = true;

  // Function to handle Login logic
  Future<void> loginUser() async {
    final body = {
      "email": emailController.text, // Assuming backend expects 'email'
      "password": passwordController.text,
    };

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/login/"), // Updated endpoint for login
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login Successful!")),
          );
          // Navigate to Home or next screen here
          // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomePage()));
        }
      } else {
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login Failed. Check credentials.")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Connection Error: $e")),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Using SingleChildScrollView to ensure it scrolls on smaller devices
      // even if it fits on larger ones now.
      body: SingleChildScrollView(
        child: Column(
          children: [

            /// HEADER
            Container(
              // CHANGED HEIGHT FROM 180 to 280 to push content down
              height: 280,
              width: double.infinity,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE88B60), Color(0xFFD96548)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -40,
                    left: -40,
                    child: CircleAvatar(
                      radius: 90,
                      backgroundColor: const Color(0xFFDCC169),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    right: -30,
                    child: CircleAvatar(
                      radius: 70,
                      backgroundColor: const Color(0xFF8AD3B5),
                    ),
                  ),
                  const SafeArea(
                    child: Center(
                      child: Text(
                        "Login Here",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32, // Kept font size from signup code
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            /// FORM BODY
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
              child: Column(
                children: [

                  /// GOOGLE BUTTON
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      side: const BorderSide(color: Colors.grey, width: 0.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Using an Icon as placeholder for the asset asset
                        Image.asset('assets/google.webp', height: 24, width: 24),
                        // If you have the asset:
                        // Image.asset('assets/google.webp', height: 24, width: 24),
                        const SizedBox(width: 8),
                        const Text(
                          "Sign in with Google",
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w600
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text("or", style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 25),

                  /// EMAIL INPUT
                  _buildTextField(emailController, "Email"),

                  const SizedBox(height: 15),

                  /// PASSWORD INPUT
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: "Password",
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  /// LOGIN BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loginUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Log In",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// FORGOT PASSWORD
                  GestureDetector(
                    onTap: () {
                      // Handle forgot password routing
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Forgot Password tapped")),
                      );
                    },
                    child: const Text(
                      "Request a New Password",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                  // Increased bottom spacing slightly to push it further down if needed

                  /// NEW HERE? LINK
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("New here? "),
                      GestureDetector(
                        onTap: () {
                          // Assuming you want to go back to signup.
                          // If Login is pushed on top of Signup:
                          Navigator.pushNamed(context, AppRoutes.signup);
                          // If they are sibling routes:
                          // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SignupPage()));
                        },
                        child: const Text(
                          "Create an account",
                          style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                   const SizedBox(height: 20), // Extra padding at very bottom
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method for text fields (kept identical to signup code)
  static Widget _buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    );
  }
}