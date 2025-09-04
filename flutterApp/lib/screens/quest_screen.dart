import 'package:flutter/material.dart';

class Quest {
  final String title;
  final String details;
  final String difficulty;
  final int points;
  bool expanded;

  Quest({
    required this.title,
    required this.details,
    required this.difficulty,
    required this.points,
    this.expanded = false,
  });
}

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key});

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  final List<Quest> _activeQuests = [
    Quest(
      title: 'Scan your next grocery receipt',
      details:
      'Snap or upload your grocery receipt. We’ll estimate carbon impact from line items (e.g., meat vs. veg).',
      difficulty: 'Easy',
      points: 10,
    ),
    Quest(
      title: 'Try one plant-based lunch',
      details:
      'Replace a single lunch with a plant-based option. Ideas: veggie wrap, tofu stir-fry, chickpea salad.',
      difficulty: 'Medium',
      points: 15,
    ),
    Quest(
      title: 'Swap dairy milk for oat/soy once',
      details: 'Choose any non-dairy milk once today (oat/soy/almond).',
      difficulty: 'Easy',
      points: 8,
    ),
  ];

  final List<Quest> _completedQuests = [];
  int _totalPoints = 0;

  void _toggleExpand(Quest q) =>
      setState(() => q.expanded = !q.expanded);

  void _completeQuest(Quest q) {
    setState(() {
      _activeQuests.remove(q);
      _completedQuests.insert(0, q);
      _totalPoints += q.points;
    });
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text('$_totalPoints pts'),
                ],
              ),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _QuestList(
              items: _activeQuests,
              mode: _ListMode.active,
              onToggleExpand: _toggleExpand,
              onComplete: _completeQuest,
            ),
            _QuestList(
              items: _completedQuests,
              mode: _ListMode.completed,
              onToggleExpand: _toggleExpand,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ListMode { active, completed }

class _QuestList extends StatelessWidget {
  final List<Quest> items;
  final _ListMode mode;
  final void Function(Quest) onToggleExpand;
  final void Function(Quest)? onComplete;

  const _QuestList({
    required this.items,
    required this.mode,
    required this.onToggleExpand,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            mode == _ListMode.active
                ? 'No active quests right now.\nCheck back soon! 🌱'
                : 'Nothing here yet.\nComplete a quest to see it here. 🎉',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (context, i) {
        final q = items[i];
        return _QuestCard(
          quest: q,
          mode: mode,
          onToggleExpand: () => onToggleExpand(q),
          onComplete: onComplete == null ? null : () => onComplete!(q),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: items.length,
    );
  }
}

class _QuestCard extends StatelessWidget {
  final Quest quest;
  final _ListMode mode;
  final VoidCallback onToggleExpand;
  final VoidCallback? onComplete;

  const _QuestCard({
    required this.quest,
    required this.mode,
    required this.onToggleExpand,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
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
          onTap: onToggleExpand,
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
                        quest.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (mode == _ListMode.active)
                      Checkbox(
                        value: false,
                        onChanged: (_) => onComplete?.call(),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    else
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 22),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(quest.details,
                            style:
                            const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _badge(quest.difficulty, Colors.blueGrey),
                            const SizedBox(width: 8),
                            _badge('${quest.points} pts', Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: quest.expanded
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
        fontSize: 12,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
