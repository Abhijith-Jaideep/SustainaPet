// lib/screens/socials_screen.dart
import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import '../api/base_url.dart';
// import '../api/pawprint_api.dart';

class SocialsScreen extends StatefulWidget {
  const SocialsScreen({super.key});

  @override
  State<SocialsScreen> createState() => _SocialsScreenState();
}

class _SocialsScreenState extends State<SocialsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final TextEditingController _idCtrl = TextEditingController();

  // ---------- DUMMY DATA (UI ONLY) ----------
  // final PawprintApi api = PawprintApi(pickBaseUrl()); // ← commented (no logic)
  // int? _me;

  final List<_Friend> _friends = const [
    _Friend(userid: 101, name: 'Ava Green'),
    _Friend(userid: 202, name: 'Leo Sun'),
    _Friend(userid: 303, name: 'Maya Blue'),
  ];

  final List<_FriendRequest> _requests = const [
    _FriendRequest(requestId: 1, fromUserId: 404, fromName: 'Sam Terra'),
    _FriendRequest(requestId: 2, fromUserId: 505, fromName: 'Rin Wave'),
  ];

  final List<_LeaderRow> _board = const [
    _LeaderRow(rank: 1, name: 'Ava Green', savedKg: 43.2, emittedKg: 12.1),
    _LeaderRow(rank: 2, name: 'You', savedKg: 38.0, emittedKg: 15.4),
    _LeaderRow(rank: 3, name: 'Leo Sun', savedKg: 25.7, emittedKg: 20.0),
    _LeaderRow(rank: 4, name: 'Maya Blue', savedKg: 19.9, emittedKg: 22.5),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);

    // ------- BOOTSTRAP (commented) -------
    // _bootstrap();
  }

  // Future<void> _bootstrap() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final raw = prefs.get('userId');
  //   int? me;
  //   if (raw is int) me = raw;
  //   if (raw is String) me = int.tryParse(raw);
  //   setState(() => _me = me);
  //   await _refreshFriends();
  //   await _refreshBoard();
  // }

  // Future<void> _refreshFriends() async {
  //   if (_me == null) return;
  //   // call api.listFriends(_me!) / api.listFriendRequests(_me!)
  // }

  // Future<void> _refreshBoard() async {
  //   if (_me == null) return;
  //   // call api.getLeaderboard(me: _me!)
  // }

  // Future<void> _sendRequest() async {
  //   final toId = int.tryParse(_idCtrl.text.trim());
  //   if (toId == null || _me == null) return;
  //   await api.sendFriendRequest(fromUserId: _me!, toUserId: toId);
  //   _idCtrl.clear();
  //   await _refreshFriends();
  // }

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                  icon: Icons.person_add_alt_1, label: 'Add Friend by User ID'),
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
                      onPressed: () {
                        // _sendRequest(); // ← hook up later
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('This is a UI stub only.')),
                        );
                      },
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

        if (_requests.isNotEmpty)
          _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(icon: Icons.mail, label: 'Requests for You'),
                const SizedBox(height: 8),
                ..._requests.map(
                      (r) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading:
                    const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text('${r.fromName} (ID ${r.fromUserId})'),
                    subtitle: const Text('Status: pending'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            onPressed: () {
                              // _respond(r.requestId, true);
                            },
                            icon: const Icon(Icons.check_circle,
                                color: Colors.green)),
                        IconButton(
                            onPressed: () {
                              // _respond(r.requestId, false);
                            },
                            icon: const Icon(Icons.cancel, color: Colors.red)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (_requests.isNotEmpty) const SizedBox(height: 16),

        _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(icon: Icons.people, label: 'Your Friends'),
              const SizedBox(height: 8),
              if (_friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No friends yet. Add someone by ID to get started!'),
                ),
              ..._friends.map(
                    (f) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(f.name),
                  subtitle: Text('ID: ${f.userid}'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- LEADERBOARD TAB ----------------
  Widget _leaderboardTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                  icon: Icons.emoji_events,
                  label: 'Leaderboard (This Month)'),
              const SizedBox(height: 8),
              ..._board.map((r) => ListTile(
                leading: _Medal(r.rank),
                title: Text(r.name,
                    style: TextStyle(
                        fontWeight: r.name == 'You'
                            ? FontWeight.w700
                            : FontWeight.w500)),
                subtitle: Text(
                    'Saved: ${r.savedKg.toStringAsFixed(1)} kg • Emitted: ${r.emittedKg.toStringAsFixed(1)} kg'),
                trailing: Text('#${r.rank}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
            ],
          ),
        ),
      ],
    );
  }
}

/* ===== Shared UI Bits (self-contained) ===== */

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

/* ===== Lightweight local models for UI only ===== */
class _Friend {
  final int userid;
  final String name;
  const _Friend({required this.userid, required this.name});
}

class _FriendRequest {
  final int requestId;
  final int fromUserId;
  final String fromName;
  const _FriendRequest({
    required this.requestId,
    required this.fromUserId,
    required this.fromName,
  });
}

class _LeaderRow {
  final int rank;
  final String name;
  final double emittedKg;
  final double savedKg;
  const _LeaderRow({
    required this.rank,
    required this.name,
    required this.emittedKg,
    required this.savedKg,
  });
}
