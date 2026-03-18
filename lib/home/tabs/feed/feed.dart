import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_app/config/config.dart';
import 'package:flutter_app/routes.dart';
import 'package:flutter_app/home/tabs/feed/post_card.dart';

const String _base = AppConfig.baseUrl;

class HomeFeed extends StatefulWidget {
  const HomeFeed({Key? key}) : super(key: key);

  @override
  State<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<HomeFeed> {
  final ScrollController _scrollController = ScrollController();

  // ── Backpack animation key ──────────────────────────────────
  final GlobalKey<_AnimatedBackpackIconState> _backpackKey =
      GlobalKey<_AnimatedBackpackIconState>();

  List<Map<String, dynamic>> _posts     = [];
  int     _page        = 1;
  bool    _hasMore     = true;
  bool    _isLoading   = true;
  bool    _isFetching  = false;
  String? _error;
  int     _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFeed(reset: true);
    _fetchUnreadCount();
    _scrollController.addListener(() {
      final pos        = _scrollController.position;
      final nearBottom = pos.pixels >= pos.maxScrollExtent - 200;
      if (nearBottom && _hasMore && !_isFetching && !_isLoading) {
        _loadFeed();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error     = null;
        _page      = 1;
        _hasMore   = true;
      });
    } else {
      if (_isFetching || !_hasMore) return;
      setState(() => _isFetching = true);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() => _isLoading = false);
        return;
      }

      final uri = Uri.parse('$_base/api/feed/').replace(
        queryParameters: {'page': '$_page', 'per_page': '10'},
      );
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Token $token'},
      );

      if (res.statusCode == 200) {
        final data  = jsonDecode(res.body);
        final posts = List<Map<String, dynamic>>.from(data['posts']);
        setState(() {
          if (reset) {
            _posts = posts;
          } else {
            _posts.addAll(posts);
          }
          _hasMore = data['has_more'] ?? false;
          _page++;
          _error = null;
        });
      } else {
        setState(() => _error = 'Failed to load feed. Please try again.');
      }
    } catch (e) {
      setState(() => _error = 'Network error. Pull down to retry.');
    } finally {
      if (mounted) setState(() {
        _isLoading  = false;
        _isFetching = false;
      });
    }
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final prev = _unreadCount;
      final res = await http.get(
        Uri.parse('$_base/api/notifications/unread-count/'),
        headers: {'Authorization': 'Token $token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data  = jsonDecode(res.body);
        final count = data['count'] ?? 0;
        setState(() => _unreadCount = count);
        // Trigger backpack animation if new notifications arrived
        if (count > prev) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _backpackKey.currentState?.triggerNotification();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _onRefresh() async {
    await _loadFeed(reset: true);
    await _fetchUnreadCount();
  }

  void _onAuthorTap(Map<String, dynamic> post) {
    final authorId   = post['author_id'];
    final authorName = post['author_name']?.toString() ?? 'User';
    Navigator.pushNamed(
      context,
      AppRoutes.otherProfile,
      arguments: {
        'user_id':   authorId,
        'user_name': authorName,
      },
    );
  }

  void _openNotifications() {
    Navigator.pushNamed(context, AppRoutes.notifications).then((_) {
      _fetchUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 52, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _loadFeed(reset: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color:     Colors.black,
      onRefresh: _onRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics:    const AlwaysScrollableScrollPhysics(),
        slivers: [

          // ── App Bar ─────────────────────────────────────────────────
          SliverAppBar(
            toolbarHeight:             56,
            pinned:                    false,
            floating:                  true,
            snap:                      true,
            elevation:                 0,
            backgroundColor:           const Color(0xFFF8F9FA),
            automaticallyImplyLeading: false,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                // ── Camera icon (create post) ───────────────────
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined,
                      color: Colors.black, size: 26),
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.post),
                ),

                // ── Logo centered ───────────────────────────────
                Expanded(
                  child: Center(
                    child: Image.asset(
                      'assets/logo.png',
                      height: 130,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // ── Animated backpack with unread badge ─────────
                GestureDetector(
                  onTap: _openNotifications,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment:   Alignment.center,
                      children: [
                        _AnimatedBackpackIcon(key: _backpackKey),
                        if (_unreadCount > 0)
                          Positioned(
                            top:   -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                  minWidth: 16, minHeight: 16),
                              child: Text(
                                _unreadCount > 99
                                    ? '99+'
                                    : '$_unreadCount',
                                style: const TextStyle(
                                  color:      Colors.white,
                                  fontSize:   9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            titleSpacing: 0,
          ),

          // ── Empty state ─────────────────────────────────────────────
          if (_posts.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.explore_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No posts yet',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('Follow people to see their travel posts here',
                        style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ),
            )

          // ── Posts list ──────────────────────────────────────────────
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _posts.length) {
                    if (_isFetching) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2),
                        ),
                      );
                    }
                    if (!_hasMore) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text("You're all caught up! ✈️",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final post = _posts[index];
                  return PostCard(
                    post:        post,
                    onAuthorTap: () => _onAuthorTap(post),
                  );
                },
                childCount: _posts.length + 1,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Animated Backpack Icon ────────────────────────────────────────────────────

class _AnimatedBackpackIcon extends StatefulWidget {
  const _AnimatedBackpackIcon({super.key});

  @override
  State<_AnimatedBackpackIcon> createState() => _AnimatedBackpackIconState();
}

class _AnimatedBackpackIconState extends State<_AnimatedBackpackIcon>
    with TickerProviderStateMixin {

  late final AnimationController _idleController;
  late final AnimationController _notifController;
  late final Animation<double>   _idleFloat;
  late final Animation<double>   _shake;
  late final Animation<double>   _bounce;
  bool _isNotifying = false;

  @override
  void initState() {
    super.initState();

    _idleController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _idleFloat = Tween<double>(begin: 0.0, end: -3.0).animate(
      CurvedAnimation(parent: _idleController, curve: Curves.easeInOut),
    );

    _notifController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    );

    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0,   end: -0.20), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.20, end:  0.20), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  0.20, end: -0.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.15, end:  0.10), weight: 2),
      TweenSequenceItem(tween: Tween(begin:  0.10, end:  0.0),  weight: 1),
    ]).animate(
      CurvedAnimation(parent: _notifController, curve: Curves.easeInOut),
    );

    _bounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.00, end: 1.28), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 1.28, end: 0.88), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.00), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _notifController, curve: Curves.easeOut),
    );

    _notifController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _isNotifying = false);
        _notifController.reset();
        _idleController.repeat(reverse: true);
      }
    });
  }

  void triggerNotification() {
    if (!mounted || _isNotifying) return;
    _idleController.stop();
    setState(() => _isNotifying = true);
    _notifController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _idleController.dispose();
    _notifController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idleController, _notifController]),
      builder: (context, _) {
        final floatY = _isNotifying ? 0.0 : _idleFloat.value;
        final rotate = _isNotifying ? _shake.value  : 0.0;
        final scale  = _isNotifying ? _bounce.value : 1.0;

        return Transform.translate(
          offset: Offset(0, floatY),
          child: Transform.rotate(
            angle:     rotate,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(
              scale: scale,
              child: SizedBox(
                width:  26,
                height: 26,
                child:  CustomPaint(painter: _BackpackPainter()),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BackpackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokePaint = Paint()
      ..color       = Colors.black
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Body
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.10, h * 0.30, w * 0.90, h * 0.88,
        Radius.circular(w * 0.18),
      ),
      strokePaint,
    );

    // Strap arc
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.36, h * 0.30)
        ..cubicTo(
            w * 0.36, h * 0.10,
            w * 0.64, h * 0.10,
            w * 0.64, h * 0.30),
      strokePaint,
    );

    // Strap base bar
    canvas.drawLine(
      Offset(w * 0.36, h * 0.30),
      Offset(w * 0.64, h * 0.30),
      strokePaint,
    );

    // Front pocket
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.28, h * 0.54, w * 0.72, h * 0.78,
        Radius.circular(w * 0.10),
      ),
      strokePaint,
    );

    // Zipper line
    canvas.drawLine(
      Offset(w * 0.35, h * 0.54),
      Offset(w * 0.65, h * 0.54),
      Paint()
        ..color       = Colors.black
        ..strokeWidth = 1.0
        ..strokeCap   = StrokeCap.round,
    );

    // Zipper pull dot
    canvas.drawCircle(
        Offset(w * 0.50, h * 0.54), w * 0.04, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}