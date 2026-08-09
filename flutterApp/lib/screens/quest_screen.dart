// lib/screens/quest_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../api/base_url.dart';
import '../api/sustainapet_api.dart';
import '../widgets/helper_icon.dart';

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key});

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  late final SustainaPetApi api;
  int? _userId;

  List<UserQuestDto> _active = [];
  List<UserQuestDto> _completed = [];
  int _points = 0;

  bool _loading = true;
  bool _assigning = false;

  // Only daily decay timers remain (weekly reset removed)
  Timer? _dailyDecayStartTimer;
  Timer? _dailyDecayRepeater;

  @override
  void initState() {
    super.initState();
    api = SustainaPetApi(pickBaseUrl());
    _bootstrap();
    _scheduleDailyDecayAtMidnight();
  }

  @override
  void dispose() {
    _dailyDecayStartTimer?.cancel();
    _dailyDecayRepeater?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  INITIAL SETUP
  // ---------------------------------------------------------------------------
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
          await prefs.setInt('userId', parsed);
        }
      }
      if (!mounted) return;

      if (uid == null) {
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      _userId = uid;

      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load quests: $e')));
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  DAILY MOOD DECAY
  // ---------------------------------------------------------------------------
  void _scheduleDailyDecayAtMidnight() {
    _dailyDecayStartTimer?.cancel();
    _dailyDecayRepeater?.cancel();

    final now = DateTime.now();
    final nextMidnight =
    DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final untilMidnight = nextMidnight.difference(now);

    _dailyDecayStartTimer = Timer(untilMidnight, () async {
      await _applyDailyMoodDecay();
      _dailyDecayRepeater = Timer.periodic(const Duration(days: 1), (_) async {
        await _applyDailyMoodDecay();
      });
    });
  }

  Future<void> _applyDailyMoodDecay() async {
    if (_userId == null) return;
    try {
      // special endpoint pattern retained from your API
      await api.completeUserQuest(-1, moodDelta: -10);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Daily mood decay failed: $e')));
    }
  }

  // ---------------------------------------------------------------------------
  //  REFRESH DATA (manual refresh button + pull to refresh)
  // ---------------------------------------------------------------------------
  Future<void> _refreshAll() async {
    if (_userId == null) return;
    final uid = _userId!;
    final active = await api.getUserQuests(uid, status: 'active');
    final done = await api.getUserQuests(uid, status: 'completed');
    final dash = await api.getDashboard(uid);

    if (!mounted) return;
    setState(() {
      _active = active;
      _completed = done;
      _points = dash.user.carbonpoints;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  //  MANUAL SHUFFLE (no timer)
  // ---------------------------------------------------------------------------
  List<UserQuestDto> _replaceInPlace(List<UserQuestDto> list, UserQuestDto item) {
    final idx = list.indexWhere((x) => x.userquestid == item.userquestid);
    if (idx < 0) return list;
    final copy = List<UserQuestDto>.from(list);
    copy[idx] = item;
    return copy;
  }

  Future<void> _assignRandom() async {
    if (_userId == null) return;
    setState(() => _assigning = true);
    try {
      final uid = _userId!;
      final activeNow = await api.getUserQuests(uid, status: 'active');
      const target = 3;

      if (activeNow.length < target) {
        final deficit = target - activeNow.length;
        await api.assignRandomQuests(
          userid: uid,
          count: deficit,
          difficulty: const ['Easy', 'Medium'],
        );
        await _refreshAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
            Text('Added $deficit quest${deficit == 1 ? '' : 's'} to keep it at $target')));
      } else {
        final firstThree = activeNow.take(target).toList();
        final updated = <UserQuestDto>[];

        for (final uq in firstThree) {
          try {
            final fresh = await api.replaceUserQuest(
              uq.userquestid,
              difficulty: [uq.quest.difficulty],
            );
            updated.add(fresh ?? uq);
          } catch (_) {
            updated.add(uq);
          }
        }

        if (!mounted) return;
        setState(() {
          var working = List<UserQuestDto>.from(_active);
          for (final item in updated) {
            working = _replaceInPlace(working, item);
          }
          _active = working;
        });

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shuffled your quests (kept it at 3)')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Shuffle failed: $e')));
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  QUEST COMPLETION (shows quest_complete.gif)
  // ---------------------------------------------------------------------------
  int _moodDeltaForDifficulty(String difficulty) {
    final d = difficulty.trim().toLowerCase();
    if (d == 'easy') return 10;
    if (d == 'medium' || d == 'med') return 25;
    if (d == 'hard') return 40;
    return 5;
  }

  Future<void> _complete(UserQuestDto uq) async {
    if (uq.iscompleted) return;

    final moodDelta = _moodDeltaForDifficulty(uq.quest.difficulty);

    // optimistic UI: move to completed list immediately
    final optimistic = uq.copyWith(
      iscompleted: true,
      completeddate: DateTime.now(),
    );
    setState(() {
      _active =
          _active.where((x) => x.userquestid != uq.userquestid).toList();
      _completed = [optimistic, ..._completed];
    });

    final savedAbsLocal = uq.quest.emissions.abs();

    // dialog with quest_complete.gif
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Quest Completed 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/eco_pet/quest_complete.gif',
              height: 180,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              uq.quest.description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.eco_rounded, color: Colors.green),
                const SizedBox(width: 6),
                Text('CO₂e saved: ${savedAbsLocal.toStringAsFixed(3)} kg'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mood, color: Colors.orange),
                const SizedBox(width: 6),
                Text('Mood +$moodDelta'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );

    try {
      await api.completeUserQuest(uq.userquestid, moodDelta: moodDelta);
      if (!mounted) return;
      setState(() {
        _points += uq.quest.reward;
      });
      await _pullOneIntoLists(uq.userquestid);
    } catch (e) {
      if (!mounted) return;
      // rollback optimistic update
      setState(() {
        _completed =
            _completed.where((x) => x.userquestid != uq.userquestid).toList();
        _active = [uq, ..._active];
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Completion failed: $e')));
    }
  }

  Future<UserQuestDto?> _replaceOne(UserQuestDto old) async {
    final diffs = [old.quest.difficulty];
    final fresh = await api.replaceUserQuest(old.userquestid, difficulty: diffs);
    if (!mounted || fresh == null) return fresh;

    setState(() {
      if (_active.any((x) => x.userquestid == fresh.userquestid)) {
        _active = _replaceInPlace(_active, fresh);
      }
      if (_completed.any((x) => x.userquestid == fresh.userquestid)) {
        _completed = _replaceInPlace(_completed, fresh);
      }
    });
    return fresh;
  }

  Future<void> _pullOneIntoLists(int userQuestId) async {
    final latest = await api.getUserQuest(userQuestId);
    if (!mounted || latest == null) return;

    setState(() {
      _active =
          _active.where((x) => x.userquestid != userQuestId).toList();
      _completed =
          _completed.where((x) => x.userquestid != userQuestId).toList();

      if (latest.iscompleted) {
        _completed = [latest, ..._completed];
      } else {
        _active = _replaceInPlace(_active, latest);
      }
    });
  }

  // ---------------------------------------------------------------------------
  //  UI
  // ---------------------------------------------------------------------------
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
          title: const Text('Quests'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
            ],
          ),
          actions: [
            HelpIcon(assetPath: 'assets/images/tutorial/quests.jpg'),
            IconButton(
              onPressed: _assigning ? null : _assignRandom,
              tooltip: 'Shuffle (keep 3)',
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
              child: Center(
                child: Text(
                  'Carbon points: $_points',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
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
                onReplaceOne: _replaceOne,
                moodDeltaForDifficulty: _moodDeltaForDifficulty,
              ),
              _UserQuestList(
                items: _completed,
                mode: _ListMode.completed,
                onReplaceOne: _replaceOne, // won't show for completed
                moodDeltaForDifficulty: _moodDeltaForDifficulty,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  SUPPORT WIDGETS
// ============================================================================
enum _ListMode { active, completed }

class _UserQuestList extends StatelessWidget {
  final List<UserQuestDto> items;
  final _ListMode mode;
  final Future<void> Function(UserQuestDto)? onCompleteChecked;
  final Future<UserQuestDto?> Function(UserQuestDto)? onReplaceOne;
  final int Function(String) moodDeltaForDifficulty;

  const _UserQuestList({
    required this.items,
    required this.mode,
    this.onCompleteChecked,
    this.onReplaceOne,
    required this.moodDeltaForDifficulty,
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
          key: ValueKey(uq.userquestid), // stable key to avoid state hopping
          uq: uq,
          mode: mode,
          onCheck: onCompleteChecked == null ? null : () => onCompleteChecked!(uq),
          onReplace: onReplaceOne == null ? null : () => onReplaceOne!(uq),
          moodDeltaForDifficulty: moodDeltaForDifficulty,
        );
      },
    );
  }
}

class _QuestCard extends StatefulWidget {
  final UserQuestDto uq;
  final _ListMode mode;
  final Future<void> Function()? onCheck;
  final Future<UserQuestDto?> Function()? onReplace;
  final int Function(String) moodDeltaForDifficulty;

  const _QuestCard({
    super.key,
    required this.uq,
    required this.mode,
    this.onCheck,
    this.onReplace,
    required this.moodDeltaForDifficulty,
  });

  @override
  State<_QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<_QuestCard> {
  bool _expanded = false;
  bool _busy = false;
  bool _replacing = false;

  void _showImpactSheet(BuildContext ctx) {
    final q = widget.uq.quest;
    final mood = widget.moodDeltaForDifficulty(q.difficulty);
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why this quest matters', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('• Estimated CO₂e impact: ${q.emissions.abs().toStringAsFixed(3)} kg saved'),
            Text('• Carbon points awarded: ${q.reward}'),
            Text('• Eco-pet mood on complete: +$mood'),
            const SizedBox(height: 12),
            const Text(
              'Method (short): Based on activity type and typical emissions factors; '
                  'we compute the kg CO₂e avoided vs a baseline. Points scale with impact and difficulty.',
              style: TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: Values are estimates and may vary with individual habits.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ),
          ],
        ),
      ),
    );
  }

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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                              Colors.teal,
                            ),
                            const SizedBox(width: 8),
                            _badge(
                              'Mood +${widget.moodDeltaForDifficulty(quest.difficulty)}',
                              Colors.orange,
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Replace only this quest
                            TextButton.icon(
                              onPressed: _replacing || isCompleted || widget.onReplace == null
                                  ? null
                                  : () async {
                                setState(() => _replacing = true);
                                try {
                                  final upd = await widget.onReplace!.call();
                                  if (upd != null && mounted) {
                                    // Parent list has already been updated; just notify.
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Quest replaced')),
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Replace failed: $e')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _replacing = false);
                                }
                              },
                              icon: _replacing
                                  ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Icon(Icons.autorenew),
                              label: const Text('Replace'),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _showImpactSheet(context),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Details'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  crossFadeState:
                  _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

// copyWith for UserQuestDto (used for optimistic UI)
extension _UserQuestCopyExt on UserQuestDto {
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
