import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../../../config/config.dart';
import '../../../routes.dart';

final _supabase = Supabase.instance.client;

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final Color _themeYellow = const Color(0xFFFFD54F);
  final Color _lightYellow = const Color(0xFFFFF9C4);

  String groupName       = 'Group Chat';
  String groupId         = '';
  int    adminId         = 0;
  int    currentUserId   = 0;
  String currentUserName = 'Me';
  bool   _isLoadingUser  = true;
  bool   _isUploading    = false;

  // Guard so didChangeDependencies only initialises once
  bool _initialized = false;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController      _scrollController  = ScrollController();

  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only run setup once — prevents re-subscription every time a child
    // route pops back to this page (e.g. returning from GroupDetailsPage).
    if (_initialized) return;
    _initialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      final rawId    = args['group_id'] ?? args['groupId'] ?? args['id'];
      final rawAdmin = args['admin_id'] ?? args['adminId'];
      setState(() {
        groupName = args['group_name']?.toString() ??
            args['groupName']?.toString() ?? 'Group Chat';
        groupId   = rawId?.toString().trim().isNotEmpty == true
            ? rawId.toString()
            : groupName.replaceAll(' ', '_').toLowerCase();
        adminId   = int.tryParse(rawAdmin?.toString() ?? '0') ?? 0;
      });
      _subscribeToMessages();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeToMessages() {
    if (groupId.isEmpty) return;
    _fetchMessages();
    _channel = _supabase
        .channel('messages:$groupId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'messages',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'group_id',
            value:  groupId,
          ),
          callback: (payload) {
            final newMsg = payload.newRecord;
            if (mounted) setState(() => _messages.insert(0, newMsg));
          },
        )
        .subscribe();
  }

  Future<void> _fetchMessages() async {
    if (groupId.isEmpty) return;
    try {
      final data = await _supabase
          .from('messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _messages = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      debugPrint('Fetch messages error: $e');
    }
  }

  // ── User loading ──────────────────────────────────────────────────────────

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    // Use getInt directly since we always store with setInt
    final id = prefs.getInt('user_id') ?? 0;

    if (id == 0) {
      await _fetchProfileFromBackend(prefs);
    } else {
      setState(() {
        currentUserId   = id;
        currentUserName = prefs.getString('first_name') ?? 'User';
        _isLoadingUser  = false;
      });
    }
  }

  Future<void> _fetchProfileFromBackend(SharedPreferences prefs) async {
    try {
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() => _isLoadingUser = false);
        return;
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/profile/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type':  'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await prefs.setInt('user_id', data['id']);
        await prefs.setString('first_name', data['first_name'] ?? 'User');
        setState(() {
          currentUserId   = data['id'];
          currentUserName = data['first_name'] ?? 'User';
          _isLoadingUser  = false;
        });
      } else {
        setState(() => _isLoadingUser = false);
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
      setState(() => _isLoadingUser = false);
    }
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  Future<void> _sendMessage({
    String  type    = 'text',
    String? fileUrl,
    String? text,
  }) async {
    final msgText = text?.trim() ?? '';
    if (msgText.isEmpty && fileUrl == null) return;
    if (groupId.isEmpty) return;
    if (currentUserId == 0) {
      await _loadUserInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identifying user... try again.')),
        );
      }
      return;
    }
    try {
      await _supabase.from('messages').insert({
        'group_id':    groupId,
        'sender_id':   currentUserId,
        'sender_name': currentUserName,
        'text':        msgText,
        'type':        type,
        'file_url':    fileUrl ?? '',
      });
      _messageController.clear();
    } catch (e) {
      debugPrint('Send message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  // ── File upload ───────────────────────────────────────────────────────────

  Future<void> _pickAndUpload(String type) async {
    File?   file;
    String? originalName;

    try {
      if (type == 'image') {
        final picked = await ImagePicker()
            .pickImage(source: ImageSource.gallery, imageQuality: 70);
        if (picked != null) {
          file = File(picked.path);
          originalName = picked.name;
        }
      } else if (type == 'video') {
        final picked =
            await ImagePicker().pickVideo(source: ImageSource.gallery);
        if (picked != null) {
          file = File(picked.path);
          originalName = picked.name;
        }
      } else if (type == 'audio') {
        final result =
            await FilePicker.platform.pickFiles(type: FileType.audio);
        if (result != null) {
          file = File(result.files.single.path!);
          originalName = result.files.single.name;
        }
      } else {
        final result = await FilePicker.platform.pickFiles();
        if (result != null) {
          file = File(result.files.single.path!);
          originalName = result.files.single.name;
        }
      }

      if (file == null) return;
      setState(() => _isUploading = true);

      final ext      = originalName?.split('.').last ?? type;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path     = '$groupId/$type/$fileName';

      await _supabase.storage.from('chat-files').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl =
          _supabase.storage.from('chat-files').getPublicUrl(path);

      await _sendMessage(
        type:    type,
        fileUrl: publicUrl,
        text:    (type == 'doc' || type == 'audio') ? originalName : null,
      );
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Attachment sheet ──────────────────────────────────────────────────────

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildAttachIcon(Icons.image,            Colors.purple, 'Photo',
                () => _pickAndUpload('image')),
            _buildAttachIcon(Icons.videocam,          Colors.pink,   'Video',
                () => _pickAndUpload('video')),
            _buildAttachIcon(Icons.headphones,        Colors.orange, 'Audio',
                () => _pickAndUpload('audio')),
            _buildAttachIcon(Icons.insert_drive_file, Colors.blue,   'File',
                () => _pickAndUpload('doc')),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachIcon(
      IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ── Navigate to group details ─────────────────────────────────────────────

  void _openGroupDetails() {
    final gid = int.tryParse(groupId) ?? 0;
    if (gid == 0) return;
    Navigator.pushNamed(
      context,
      AppRoutes.groupDetails,
      arguments: {
        'group_id':   gid,
        'group_name': groupName,
        'admin_id':   adminId,
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          groupName,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _openGroupDetails,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isUploading)
            LinearProgressIndicator(
                color: _themeYellow, backgroundColor: Colors.black12),

          Expanded(
            child: (_isLoadingUser || groupId.isEmpty)
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.black))
                : _messages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Start the conversation!',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg     = _messages[index];
                          final isMe    = msg['sender_id'].toString() ==
                              currentUserId.toString();
                          final isAdmin = msg['sender_id'].toString() ==
                              adminId.toString();
                          final senderId =
                              int.tryParse(msg['sender_id'].toString()) ?? 0;
                          return MessageBubble(
                            sender:        msg['sender_name'] ?? 'Unknown',
                            senderId:      senderId,
                            text:          msg['text']     ?? '',
                            type:          msg['type']     ?? 'text',
                            fileUrl:       msg['file_url'] ?? '',
                            createdAt:     msg['created_at'],
                            isMe:          isMe,
                            isAdmin:       isAdmin,
                            themeYellow:   _themeYellow,
                            lightYellow:   _lightYellow,
                            currentUserId: currentUserId,
                          );
                        },
                      ),
          ),

          // ── Input bar ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color:      Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset:     const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: Colors.black, size: 28),
                    onPressed: _showAttachmentSheet,
                  ),
                  Expanded(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                            hintText: 'Message...',
                            border: InputBorder.none),
                        minLines: 1,
                        maxLines: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        _sendMessage(text: _messageController.text),
                    child: CircleAvatar(
                      backgroundColor: Colors.black,
                      radius: 22,
                      child: Icon(Icons.send, color: _themeYellow, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class MessageBubble extends StatelessWidget {
  final String  sender;
  final int     senderId;
  final String  text;
  final String  type;
  final String  fileUrl;
  final String? createdAt;
  final bool    isMe;
  final bool    isAdmin;
  final Color   themeYellow;
  final Color   lightYellow;
  final int     currentUserId;

  const MessageBubble({
    super.key,
    required this.sender,
    required this.senderId,
    required this.text,
    required this.type,
    required this.fileUrl,
    required this.createdAt,
    required this.isMe,
    required this.isAdmin,
    required this.themeYellow,
    required this.lightYellow,
    required this.currentUserId,
  });

  String get _timeStr {
    if (createdAt == null) return '...';
    try {
      return DateFormat('hh:mm a')
          .format(DateTime.parse(createdAt!).toLocal());
    } catch (_) {
      return '...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name — tappable to open other profile
            Padding(
              padding:
                  const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: isMe
                        ? null
                        : () => Navigator.pushNamed(
                              context,
                              AppRoutes.otherProfile,
                              arguments: {
                                'user_id':   senderId,
                                'user_name': sender,
                              },
                            ),
                    child: Text(
                      isMe ? 'You' : sender,
                      style: TextStyle(
                        fontSize:   11,
                        fontWeight: FontWeight.bold,
                        color: isMe ? Colors.grey[700] : Colors.black87,
                        decoration: isMe
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                    ),
                  ),
                  if (isAdmin)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('ADMIN',
                          style: TextStyle(
                              fontSize:   9,
                              color:      Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),

            // Bubble
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:  isMe ? themeYellow : lightYellow,
                border: isAdmin
                    ? Border.all(color: Colors.black, width: 1.5)
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  isMe
                      ? const Radius.circular(16)
                      : Radius.zero,
                  bottomRight: isMe
                      ? Radius.zero
                      : const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                      color:      Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset:     const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMediaContent(context),
                  if (text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(text,
                          style: const TextStyle(
                              fontSize: 15, color: Colors.black87)),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _timeStr,
                      style: TextStyle(
                          fontSize:  10,
                          color:     Colors.black.withOpacity(0.5),
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent(BuildContext context) {
    if (type == 'text' || fileUrl.isEmpty) return const SizedBox.shrink();

    if (type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          fileUrl,
          loadingBuilder: (ctx, child, p) => p == null
              ? child
              : Container(
                  height: 150,
                  width:  200,
                  color:  Colors.white54,
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))),
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image),
        ),
      );
    }

    if (type == 'video') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white54,
            borderRadius: BorderRadius.circular(10)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill, color: Colors.black, size: 30),
            SizedBox(width: 8),
            Text('Video', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.open_in_new, size: 16),
          ],
        ),
      );
    }

    if (type == 'audio') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white54,
            borderRadius: BorderRadius.circular(10)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones, color: Colors.black),
            SizedBox(width: 8),
            Text('Audio file',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    // Generic file
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white54,
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_file, color: Colors.black),
          const SizedBox(width: 8),
          Text(type.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}