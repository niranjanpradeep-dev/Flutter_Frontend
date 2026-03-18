import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_app/config/config.dart';
import 'package:flutter_app/routes.dart';

class GroupDetailsPage extends StatefulWidget {
  final int    groupId;
  final String groupName;
  final int    adminId;

  const GroupDetailsPage({
    Key? key,
    required this.groupId,
    required this.groupName,
    required this.adminId,
  }) : super(key: key);

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  bool   _isLoading  = true;
  bool   _isSaving   = false;
  bool   _isEditing  = false;

  String _groupName     = '';
  int    _adminId       = 0;
  int    _currentUserId = 0;
  List   _members       = [];

  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _groupName      = widget.groupName;
    _adminId        = widget.adminId;
    _nameController = TextEditingController(text: widget.groupName);
    _loadCurrentUser();
    _loadGroupDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    // Use getInt directly — group.dart always saves with setInt
    final id = prefs.getInt('user_id') ?? 0;
    if (id != 0) {
      setState(() => _currentUserId = id);
    } else {
      // Fallback: fetch from backend if not cached yet
      final token = prefs.getString('auth_token');
      if (token == null) return;
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
          await prefs.setInt('user_id', data['id'] as int);
          if (mounted) setState(() => _currentUserId = data['id'] as int);
        }
      } catch (e) {
        debugPrint('Error loading user: $e');
      }
    }
  }

  Future<void> _loadGroupDetails() async {
    setState(() => _isLoading = true);
    try {
      final token    = await _getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/groups/${widget.groupId}/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _groupName           = data['group_name'] ?? _groupName;
          _adminId             = data['admin_id']   ?? _adminId;
          _members             = data['members']    ?? [];
          _nameController.text = _groupName;
        });
      } else {
        _showSnack('Failed to load group details');
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGroupName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      _showSnack('Group name cannot be empty');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final token    = await _getToken();
      final response = await http.patch(
        Uri.parse(
            '${AppConfig.baseUrl}/api/groups/${widget.groupId}/rename/'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Token $token',
        },
        body: jsonEncode({'group_name': newName}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _groupName = data['group_name'];
          _isEditing = false;
        });
        _showSnack('Group name updated ✓');
      } else if (response.statusCode == 403) {
        _showSnack('Only the admin can rename the group');
        setState(() => _isEditing = false);
      } else {
        _showSnack('Failed to update name');
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openProfile(int userId, String userName) {
    Navigator.pushNamed(
      context,
      AppRoutes.otherProfile,
      arguments: {'user_id': userId, 'user_name': userName},
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = _currentUserId != 0 && _currentUserId == _adminId;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.black))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child:
                              const Icon(Icons.arrow_back_ios, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text('Group Info',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                  // ── Group name card ───────────────────────────────────
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.group,
                                size: 18, color: Colors.black54),
                            const SizedBox(width: 8),
                            const Text('Group Name',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const Spacer(),
                            if (isAdmin)
                              GestureDetector(
                                onTap: () {
                                  if (_isEditing) {
                                    _saveGroupName();
                                  } else {
                                    setState(() => _isEditing = true);
                                  }
                                },
                                child: _isSaving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black))
                                    : Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _isEditing
                                              ? Colors.black
                                              : Colors.transparent,
                                          border: Border.all(
                                              color: Colors.black),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          _isEditing ? 'Save' : 'Edit',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _isEditing
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _isEditing
                            ? TextField(
                                controller: _nameController,
                                autofocus: true,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  border: UnderlineInputBorder(),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              )
                            : Text(
                                _groupName,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                      ],
                    ),
                  ),

                  // ── Members header ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        const Text('Members',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_members.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Members list ──────────────────────────────────────
                  Expanded(
                    child: _members.isEmpty
                        ? const Center(
                            child: Text('No members found',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            itemCount: _members.length,
                            itemBuilder: (context, index) {
                              final member        = _members[index];
                              final memberId      = member['user_id'] as int;
                              final name          =
                                  member['name'] as String? ?? 'Unknown';
                              final isAdminMember =
                                  member['is_admin'] == true;
                              final isMe =
                                  memberId == _currentUserId;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 4),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14)),
                                elevation: 0,
                                color: isMe
                                    ? const Color(0xFFFFF9C4)
                                    : const Color(0xFFF9F9F9),
                                child: ListTile(
                                  onTap: () =>
                                      _openProfile(memberId, name),
                                  leading: CircleAvatar(
                                    backgroundColor: isAdminMember
                                        ? Colors.black
                                        : const Color(0xFFE0E0E0),
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: isAdminMember
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    isMe ? '$name (You)' : name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      decoration:
                                          TextDecoration.underline,
                                    ),
                                  ),
                                  trailing: isAdminMember
                                      ? Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text('ADMIN',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.bold)),
                                        )
                                      : const Icon(Icons.chevron_right,
                                          color: Colors.grey),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}