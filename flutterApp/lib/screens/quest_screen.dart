// lib/screens/quest_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../api/base_url.dart';
import '../api/pawprint_api.dart';

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key});

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  late final PawprintApi api;
  int? _userId;

  List<UserQuestDto> _active = [];
  List<UserQuestDto> _completed = [];
  int _points = 0;

  bool _loading = true;
  bool _assigning = false;

  Timer? _weeklyResetTimer;
  Timer? _dailyDecayStartTimer;   // fires at next midnight
  Timer? _dailyDecayRepeater;     // repeats every 24h after the first midnight

  @override
  void initState() {
    super.initState();
    api = PawprintApi(pickBaseUrl());
    _bootstrap();
    _setupWeeklyReset();
    _scheduleDailyDecayAtMidnight(); // schedule daily mood -10
  }

  @override
  void dispose() {
    _weeklyResetTimer?.cancel();
    _dailyDecayStartTimer?.cancel();
    _dailyDecayRepeater?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.get('userId');
      int? uid;
      if (raw is int) {
        uid = raw;
      } else if (raw is String) {
        final parsed = int.tryParse(raw);
        if (parsed != null) {
          uid = parsed;
          await prefs.setInt('userId', parsed); // migrate
        }
      }
      if (!mounted) return;

      if (uid == null) {
        // If you don't have '/login' registered, push your login screen directly.
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      _userId = uid;

      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load quests: $e')),
      );
      setState(() => _loading = false);
    }
  }

  /// Weekly reset at next Monday 00:00 local time.
  void _setupWeeklyReset() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final weekday = todayMidnight.weekday; // 1=Mon..7=Sun
    final raw = (8 - weekday) % 7; // 0 => today; push to next week
    final daysUntilNextMonday = raw == 0 ? 7 : raw;
    final resetTime = todayMidnight.add(Duration(days: daysUntilNextMonday));
    final duration = resetTime.difference(now);

    _weeklyResetTimer?.cancel();
    _weeklyResetTimer = Timer(duration, () async {
      await _assignRandom();
      _setupWeeklyReset(); // schedule again
    });
  }

  /// Schedules the first decay exactly at local midnight, then every 24h.
  void _scheduleDailyDecayAtMidnight() {
    _dailyDecayStartTimer?.cancel();
    _dailyDecayRepeater?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final untilMidnight = nextMidnight.difference(now);

    _dailyDecayStartTimer = Timer(untilMidnight, () async {
      await _applyDailyMoodDecay();
      // After first midnight fire, repeat every 24h
      _dailyDecayRepeater = Timer.periodic(const Duration(days: 1), (_) async {
        await _applyDailyMoodDecay();
      });
    });
  }

  /// Uses existing API: completeUserQuest with a sentinel id and moodDelta -10.
  Future<void> _applyDailyMoodDecay() async {
    if (_userId == null) return;
    try {
      // Backend should apply moodDelta even if quest id -1 is ignored.
      await api.completeUserQuest(-1, moodDelta: -10);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      // Non-blocking: just toast; try again next day.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daily mood decay failed: $e')),
      );
    }
  }

  Future<void> _refreshAll() async {
    if (_userId == null) return;
    final uid = _userId!;
    final active = await api.getUserQuests(uid, status: 'active');
    final done   = await api.getUserQuests(uid, status: 'completed');
    final dash   = await api.getDashboard(uid);

    if (!mounted) return;
    setState(() {
      _active = active;
      _completed = done;
      _points = dash.user.carbonpoints;
      _loading = false;
    });
  }

  Future<void> _assignRandom() async {
    if (_userId == null) return;
    setState(() => _assigning = true);
    try {
      await api.assignRandomQuests(
        userid: _userId!,
        count: 3,
        difficulty: const ['Easy', 'Medium'],
      );
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assigned 3 new quests!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assign failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  /// Mood delta based on difficulty.
  int _moodDeltaForDifficulty(String difficulty) {
    final d = difficulty.trim().toLowerCase();
    if (d == 'easy') return 10;
    if (d == 'medium' || d == 'med') return 25;
    if (d == 'hard') return 40;
    return 5; // fallback
  }

  /// Completes a quest with optimistic UI and rollback on failure.
  Future<void> _complete(UserQuestDto uq) async {
    if (uq.iscompleted) return;

    final moodDelta = _moodDeltaForDifficulty(uq.quest.difficulty);

    // Optimistic: move from active -> completed instantly
    final optimistic = uq.copyWith(
      iscompleted: true,
      completeddate: DateTime.now(),
    );
    setState(() {
      _active = _active.where((x) => x.userquestid != uq.userquestid).toList();
      _completed = [optimistic, ..._completed];
    });

    // Success dialog (no network wait)
    final savedAbsLocal = uq.quest.emissions.abs();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Quest completed 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(uq.quest.description),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.eco_rounded, color: Colors.green),
                const SizedBox(width: 8),
                Text('CO₂e saved: ${savedAbsLocal.toStringAsFixed(3)} kg'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 8),
                Text('+${uq.quest.reward} points'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.mood, color: Colors.orange),
                SizedBox(width: 8),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text('Mood +$moodDelta'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nice!'),
          ),
        ],
      ),
    );

    // Network call; on error, rollback
    try {
      await api.completeUserQuest(uq.userquestid, moodDelta: moodDelta);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _completed = _completed.where((x) => x.userquestid != uq.userquestid).toList();
        _active = [uq, ..._active];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completion failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Quest System'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _assigning ? null : _assignRandom,
              tooltip: 'Assign 3 random',
              icon: _assigning
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.shuffle_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text('$_points pts'),
                ],
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          child: TabBarView(
            children: [
              _UserQuestList(
                items: _active,
                mode: _ListMode.active,
                onCompleteChecked: _complete,
              ),
              _UserQuestList(
                items: _completed,
                mode: _ListMode.completed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ListMode { active, completed }

class _UserQuestList extends StatelessWidget {
  final List<UserQuestDto> items;
  final _ListMode mode;
  final Future<void> Function(UserQuestDto)? onCompleteChecked;

  const _UserQuestList({
    required this.items,
    required this.mode,
    this.onCompleteChecked,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  mode == _ListMode.active
                      ? 'No active quests right now.\nTap the shuffle icon to get some 🌱'
                      : 'Nothing here yet.\nComplete a quest to see it here. 🎉',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final uq = items[i];
        return _QuestCard(
          uq: uq,
          mode: mode,
          onCheck: onCompleteChecked == null ? null : () => onCompleteChecked!(uq),
        );
      },
    );
  }
}

class _QuestCard extends StatefulWidget {
  final UserQuestDto uq;
  final _ListMode mode;
  final Future<void> Function()? onCheck;

  const _QuestCard({
    required this.uq,
    required this.mode,
    this.onCheck,
  });

  @override
  State<_QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<_QuestCard> {
  bool _expanded = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final quest = widget.uq.quest;
    final isCompleted = widget.mode == _ListMode.completed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined,
                        color: Colors.orange, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        quest.description,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ),
                    if (isCompleted)
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 22)
                    else
                      InkWell(
                        onTap: () {
                          if (_busy) return;
                          HapticFeedback.selectionClick();
                          setState(() => _busy = true);
                          if (widget.onCheck != null) {
                            widget.onCheck!().whenComplete(() {
                              if (mounted) setState(() => _busy = false);
                            });
                          } else {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: _busy
                              ? const SizedBox(
                            key: ValueKey('busy'),
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                              : const Icon(
                            key: ValueKey('check'),
                            Icons.check_box_outline_blank,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _badge(quest.difficulty, Colors.blueGrey),
                            const SizedBox(width: 8),
                            _badge('${quest.reward} pts', Colors.green),
                            const SizedBox(width: 8),
                            _badge(
                                '${quest.emissions.abs().toStringAsFixed(3)} kg CO₂e',
                                Colors.teal),
                          ],
                        ),
                        if (widget.uq.completeddate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Completed: ${widget.uq.completeddate!.toIso8601String().split('T')[0]}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ],
                    ),
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 160),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: color.withOpacity(0.1),
    ),
    child: Text(
      text,
      style: TextStyle(
          fontSize: 12, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

extension _Copy on UserQuestDto {
  UserQuestDto copyWith({
    bool? iscompleted,
    DateTime? completeddate,
  }) {
    return UserQuestDto(
      userquestid: userquestid,
      userid: userid,
      questid: questid,
      isactive: isactive,
      iscompleted: iscompleted ?? this.iscompleted,
      completeddate: completeddate ?? this.completeddate,
      quest: quest,
    );
  }
}
