// lib/screens/socials_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/base_url.dart';
import '../api/pawprint_api.dart';
import '../widgets/ecopet.dart';

// NOTE: This file expects you have `HelpIconTabAware` in widgets/helper_icon.dart
// (the tab-aware version that accepts a TabController and assetsByIndex map)
import '../widgets/helper_icon.dart';

class SocialsScreen extends StatefulWidget {
  const SocialsScreen({super.key});

  @override
  State<SocialsScreen> createState() => _SocialsScreenState();
}

class _SocialsScreenState extends State<SocialsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final PawprintApi api;

  final TextEditingController _idCtrl = TextEditingController();

  int? _me;

  // Live data
  List<FriendDto> _friends = const [];
  List<FriendRequestDto> _requests = const [];
  List<FriendsLeaderboardRowDto> _leaderboard = const [];

  // Loading/error flags
  bool _loadingFriends = false;
  bool _loadingRequests = false;
  bool _loadingBoard = false;
  String? _errorFriends;
  String? _errorRequests;
  String? _errorBoard;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    api = PawprintApi(pickBaseUrl());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get('userId');
    int? me;
    if (raw is int) me = raw;
    if (raw is String) me = int.tryParse(raw);

    setState(() => _me = me);
    if (me != null) {
      await Future.wait([
        _refreshFriends(),
        _refreshRequests(),
        _refreshBoard(),
      ]);
    }
  }

  Future<void> _refreshFriends() async {
    if (_me == null) return;
    setState(() {
      _loadingFriends = true;
      _errorFriends = null;
    });
    try {
      final data = await api.listFriends(_me!);
      setState(() => _friends = data);
    } catch (e) {
      setState(() => _errorFriends = '$e');
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _refreshRequests() async {
    if (_me == null) return;
    setState(() {
      _loadingRequests = true;
      _errorRequests = null;
    });
    try {
      final data = await api.listFriendRequests(_me!);
      setState(() => _requests = data);
    } catch (e) {
      setState(() => _errorRequests = '$e');
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _refreshBoard() async {
    if (_me == null) return;
    setState(() {
      _loadingBoard = true;
      _errorBoard = null;
    });
    try {
      final data = await api.getFriendsLeaderboard(_me!);
      setState(() => _leaderboard = data);
    } catch (e) {
      setState(() => _errorBoard = '$e');
    } finally {
      if (mounted) setState(() => _loadingBoard = false);
    }
  }

  Future<void> _sendRequest() async {
    final toId = int.tryParse(_idCtrl.text.trim());
    if (toId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid numeric User ID.')),
      );
      return;
    }
    if (_me == null) return;
    if (toId == _me) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't send a request to yourself.")),
      );
      return;
    }
    try {
      await api.sendFriendRequest(fromUserId: _me!, toUserId: toId);
      if (!mounted) return;
      _idCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request sent!')),
      );
      await _refreshRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send request: $e')),
      );
    }
  }

  Future<void> _respond(int requestId, bool accept) async {
    if (_me == null) return;
    try {
      await api.respondFriendRequest(
        userid: _me!,
        requestId: requestId,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Request accepted.' : 'Request rejected.'),
        ),
      );
      await Future.wait([
        _refreshRequests(),
        _refreshFriends(),
        _refreshBoard(),
      ]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process request: $e')),
      );
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7DA),
      appBar: AppBar(
        title: const Text('Socials'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.group_add), text: 'Friends'),
            Tab(icon: Icon(Icons.emoji_events), text: 'Leaderboard'),
          ],
        ),
        actions: [
          // 👇 tab-aware help icon (uses assets for each tab)
          HelpIconTabAware(
            controller: _tab,
            assetsByIndex: const {
              0: 'assets/images/tutorial/socials.jpg',      // Friends tab walkthrough
              1: 'assets/images/tutorial/leaderboard.jpg',  // Leaderboard tab walkthrough
            },
            fallbackAsset: 'assets/images/tutorial/socials.jpg',
          ),
          if (_me != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: () async {
                await Future.wait([
                  _refreshFriends(),
                  _refreshRequests(),
                  _refreshBoard(),
                ]);
              },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _friendsTab(context),
          _leaderboardTab(context),
        ],
      ),
    );
  }

  // ---------------- FRIENDS TAB ----------------
  Widget _friendsTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _refreshFriends(),
          _refreshRequests(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Your User ID
          _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.verified_user, label: 'Your Account'),
                const SizedBox(height: 8),
                if (_me == null)
                  const Text(
                    'Sign in to see your user ID.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFF3CD), Color(0xFFFFF9E6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Color(0xFFFFD55C)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE07A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.badge, color: Colors.black87),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your User ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_me',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: '$_me'));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User ID copied')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Add Friend
          _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(
                    icon: Icons.person_add_alt_1, label: 'Add Friend'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _idCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Enter User ID',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _me == null ? null : _sendRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Requests for You
          _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.mail, label: 'Requests for You'),
                const SizedBox(height: 8),
                if (_me == null)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Sign in to view friend requests.'),
                  )
                else if (_loadingRequests)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorRequests != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Error: $_errorRequests',
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  else if (_requests.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No pending requests.'),
                      )
                    else
                      ..._requests.map(
                            (r) => ListTile(
                          contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(
                            r.fromName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Accept',
                                onPressed: () => _respond(r.requestId, true),
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                              ),
                              IconButton(
                                tooltip: 'Reject',
                                onPressed: () => _respond(r.requestId, false),
                                icon: const Icon(Icons.cancel, color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Your Friends
          _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.people, label: 'Your Friends'),
                const SizedBox(height: 8),
                if (_me == null)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Sign in to see your friends.'),
                  )
                else if (_loadingFriends)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorFriends != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Error: $_errorFriends',
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  else if (_friends.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No friends yet. Add someone to get started!'),
                      )
                    else
                      ..._friends.map(
                            (f) => ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(
                            f.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- LEADERBOARD TAB ----------------
  Widget _leaderboardTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshBoard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(
                    icon: Icons.emoji_events, label: 'Leaderboard (This Week)'),
                const SizedBox(height: 8),
                if (_me == null)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Sign in to view your leaderboard.'),
                  )
                else if (_loadingBoard)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorBoard != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Error: $_errorBoard',
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  else if (_leaderboard.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No leaderboard to show yet.'),
                      )
                    else
                      ..._sortedByNetImpact(_leaderboard).indexed.map((entry) {
                        final idx = entry.$1;
                        final r = entry.$2;
                        final rank = idx + 1;
                        final isMe = r.userid == _me;

                        final emitted = _asDouble(r.weeklyEmissionsProduced);
                        final savedRaw = _asDouble(r.weeklyEmissionsSaved); // maybe negative
                        final savedMag = savedRaw < 0 ? -savedRaw : savedRaw;
                        final net = savedMag - emitted;

                        // Use the leaderboard row’s OWN pet mood score (0–100)
                        final int moodScore = (r.ecopetmood ?? 50);
                        final PetMood mood = petMoodFromScore(
                          moodScore.clamp(0, 100),
                        );

                        return ListTile(
                          leading: _Medal(rank),
                          title: Text(
                            isMe ? '${r.name} (You)' : r.name,
                            style: TextStyle(
                              fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Saved: ${savedMag.toStringAsFixed(1)} kg • '
                                'Emitted: ${emitted.toStringAsFixed(1)} kg • '
                                'Net: ${net.toStringAsFixed(1)} kg',
                          ),
                          // Tiny EcoPet at right using **their** mood
                          trailing: SizedBox(
                            width: 36,
                            height: 36,
                            child: EcoPet(mood: mood, size: 36),
                          ),
                        );
                      }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helpers for leaderboard math
  double _asDouble(num? n) => n == null ? 0.0 : n.toDouble();

  List<FriendsLeaderboardRowDto> _sortedByNetImpact(
      List<FriendsLeaderboardRowDto> rows) {
    final copy = [...rows];
    copy.sort((a, b) {
      final aEm = _asDouble(a.weeklyEmissionsProduced);
      final aSavedMag = _asDouble(a.weeklyEmissionsSaved);
      final aNet = (aSavedMag < 0 ? -aSavedMag : aSavedMag) - aEm;

      final bEm = _asDouble(b.weeklyEmissionsProduced);
      final bSavedMag = _asDouble(b.weeklyEmissionsSaved);
      final bNet = (bSavedMag < 0 ? -bSavedMag : bSavedMag) - bEm;

      // Descending by net
      return bNet.compareTo(aNet);
    });
    return copy;
  }
}

/* ===== Shared UI Bits ===== */

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFC107)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _Medal extends StatelessWidget {
  final int rank;
  const _Medal(this.rank, {super.key});

  @override
  Widget build(BuildContext context) {
    Color c;
    if (rank == 1) {
      c = const Color(0xFFFFD700);
    } else if (rank == 2) {
      c = const Color(0xFFC0C0C0);
    } else if (rank == 3) {
      c = const Color(0xFFCD7F32);
    } else {
      c = Colors.grey.shade300;
    }
    return CircleAvatar(
      backgroundColor: c,
      child: Text('$rank', style: const TextStyle(color: Colors.black)),
    );
  }
}
