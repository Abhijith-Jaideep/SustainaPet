// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import '../api/base_url.dart';
import '../api/pawprint_api.dart';

enum Timeframe { day, week, month }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final PawprintApi api;

  Future<_DashData>? _future;
  int? _userId;

  Future<void> _initializeDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get('userId');
    int? uid;
    if (raw is int) {
      uid = raw;
    } else if (raw is String) {
      uid = int.tryParse(raw);
      if (uid != null) await prefs.setInt('userId', uid); // migrate to int
    }
    if (uid == null) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/');
      return;
    }

    _userId = uid;
    _future = _load(uid);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    api = PawprintApi(pickBaseUrl());
    _initializeDashboard();
  }

  Future<_DashData> _load(int uid) async {
    // 1) Weekly counters + user
    final dash = await api.getDashboard(uid);
    final user = dash.user;

    // 2) Monthly + conversions + events
    final monthly = await api.getMonthlyEmissions(userid: uid);
    final conversions = await api.getConversions();
    final events = await api.getUserEvents(uid, limit: 25);

    // ===== Pending receipt adjustment (monthly visuals only) =====
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getDouble('pending_receipt_emissions_$uid') ?? 0.0;
    final pendingDesc = prefs.getString('pending_receipt_desc');
    final pendingTsStr = prefs.getString('pending_receipt_ts');
    final pendingTs = pendingTsStr != null
        ? DateTime.tryParse(pendingTsStr) ?? DateTime.now()
        : DateTime.now();

    // Keep existing monthly-signed series (used nowhere for bars now, but keep for net)
    final weeklySorted = [...monthly.weekly]..sort((a, b) => a.week.compareTo(b.week));
    final weeklyNet = weeklySorted.map((w) => w.kg.toDouble()).toList();

    // === TOP CARDS (weekly from backend; saved can be negative) ===
    double emittedWeekly = user.weeklyEmissionsProduced; // >= 0 (backend)
    double savedWeekly = user.weeklyEmissionsSaved;       // <= 0 (backend)

    // Adjust monthly net for pending receipt and inject an event row so UI shows it
    double adjustedNet = monthly.netKg;
    if (pending.abs() > 1e-9) {
      adjustedNet += pending;
      events.insert(
        0,
        EventDto(
          eventid: 0,
          userid: uid,
          userquestid: null,
          description: _prettifyReceiptDesc(pendingDesc),
          type: 'Receipt',
          emissions: pending,
          datetime: pendingTs,
        ),
      );
      await prefs.remove('pending_receipt_emissions_$uid');
      await prefs.remove('pending_receipt_desc');
      await prefs.remove('pending_receipt_ts');
    }

    // If backend weekly numbers are zero or NaN, fallback: compute last 7 days from events
    if ((emittedWeekly == 0.0 && savedWeekly == 0.0) ||
        emittedWeekly.isNaN || savedWeekly.isNaN) {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      double pos = 0.0;
      double neg = 0.0;
      for (final e in events) {
        if (e.datetime.isAfter(sevenDaysAgo)) {
          if (e.emissions > 0) pos += e.emissions;
          if (e.emissions < 0) neg += e.emissions;
        }
      }
      emittedWeekly = pos;
      savedWeekly = neg; // keep negative
    }

    final totalDisplayKg = adjustedNet.abs();

    // ----- Conversions -----
    final byName = {for (final c in conversions) c.name.toLowerCase(): c};
    final List<_Metric> metrics = [];

    final tree = byName['tree'];
    if (tree != null) {
      metrics.add(_Metric(
        id: tree.metricid,
        name: tree.name,
        description: tree.description ?? 'CO₂ absorbed by trees',
        emissionsPerX: tree.emissionsPerX,
        calculation: _CalcType.userOverEmissionsPerX,
        unitLabel: 'trees',
        icon: Icons.park_rounded,
        sentence: (v) => '≈ ${_formatNumber(v)} trees saved in a month.',
      ));
    }

    const kgPerKwh = 0.7;
    metrics.add(_Metric(
      id: 9991,
      name: 'Electricity',
      description: 'kWh equivalent',
      emissionsPerX: -kgPerKwh,
      calculation: _CalcType.electricityTimesEmissionsPerX,
      unitLabel: 'kWh',
      icon: Icons.bolt_rounded,
      overrideCompute: (emissionsKg, _) => emissionsKg / kgPerKwh,
      sentence: (v) => '≈ ${_formatNumber(v)} kWh of electricity in a month.',
    ));

    final bulb = byName['lightbulb'];
    if (bulb != null) {
      metrics.add(_Metric(
        id: bulb.metricid,
        name: bulb.name,
        description: bulb.description ?? 'LED usage hours',
        emissionsPerX: bulb.emissionsPerX,
        calculation: _CalcType.userOverEmissionsPerX,
        unitLabel: 'hours',
        icon: Icons.lightbulb_outline_rounded,
        sentence: (v) => '≈ ${_formatNumber(v)} hours of LED usage in a month.',
      ));
    }

    final phone = byName['smartphone'];
    if (phone != null) {
      metrics.add(_Metric(
        id: phone.metricid,
        name: phone.name,
        description: phone.description ?? 'Full charge cycles',
        emissionsPerX: phone.emissionsPerX,
        calculation: _CalcType.userOverEmissionsPerX,
        unitLabel: 'charges',
        icon: Icons.smartphone_rounded,
        sentence: (v) => '≈ ${_formatNumber(v)} full smartphone charges in a month.',
      ));
    }

    final car = byName['car'];
    if (car != null) {
      metrics.add(_Metric(
        id: car.metricid,
        name: car.name,
        description: car.description ?? 'Car travel distance',
        emissionsPerX: car.emissionsPerX,
        calculation: _CalcType.userOverEmissionsPerX,
        unitLabel: 'km',
        icon: Icons.directions_car_rounded,
        sentence: (v) => '≈ ${_formatNumber(v)} km of car travel in a month.',
      ));
    }

    // ====== Streak ======
    final nowLocal = DateTime.now();
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final Set<String> eventDays = {
      for (final e in events)
        _fmtDate(DateTime(e.datetime.year, e.datetime.month, e.datetime.day))
    };

    int streak = 0;
    DateTime cursor =
    eventDays.contains(_fmtDate(today)) ? today : today.subtract(const Duration(days: 1));

    while (eventDays.contains(_fmtDate(cursor))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    int carbonPoints = prefs.getInt('carbon_points_$uid') ?? 0;
    int lastRewardMultiple = prefs.getInt('streak_last_multiple_$uid') ?? 0;

    final currentMultiple = streak ~/ 7;
    if (currentMultiple > lastRewardMultiple && currentMultiple > 0) {
      final earned = 100 * (currentMultiple - lastRewardMultiple);
      carbonPoints += earned;
      await prefs.setInt('carbon_points_$uid', carbonPoints);
      await prefs.setInt('streak_last_multiple_$uid', currentMultiple);

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2E7D32),
              content: Text(
                  '🔥 Streak reward! +$earned carbon points for ${currentMultiple * 7}-day streak'),
            ),
          );
        });
      }
    }

    // ====== Build weekly charts FROM EVENTS for the CURRENT MONTH ======
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = (now.month == 12)
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);

    // 5 buckets (W1..W5). Some months only fill 4; that’s fine.
    final List<double> weeklyEmitted = List.filled(5, 0.0);
    final List<double> weeklySaved = List.filled(5, 0.0);

    for (final e in events) {
      if (!e.datetime.isBefore(monthStart) && e.datetime.isBefore(monthEnd)) {
        final day = e.datetime.day; // 1..31
        final idx = ((day - 1) / 7).floor().clamp(0, 4); // 0..4
        if (e.emissions > 0) {
          weeklyEmitted[idx] += e.emissions;
        } else if (e.emissions < 0) {
          weeklySaved[idx] += e.emissions.abs(); // store magnitude for green chart
        }
      }
    }

    final List<String> weekLabels = List.generate(5, (i) => 'W${i + 1}');

    return _DashData(
      emittedKg: emittedWeekly,
      savedKg: savedWeekly,
      totalDisplayKg: totalDisplayKg,
      weeklyNet: weeklyNet,                // kept for completeness
      weeklyEmitted: weeklyEmitted,        // NEW: from events
      weeklySaved: weeklySaved,            // NEW: from events (magnitudes)
      weekLabels: weekLabels,              // W1..W5
      metrics: metrics,
      events: events,
      streakDays: streak,
      carbonPoints: carbonPoints,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF7DA),
      appBar: AppBar(title: const Text('Dashboard')),
      body: SafeArea(
        child: FutureBuilder<_DashData>(
          future: _future,
          builder: (context, snap) {
            if (_future == null || snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                    const SizedBox(height: 10),
                    Text('Failed to load dashboard:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        final id = _userId;
                        if (id != null) setState(() => _future = _load(id));
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            if (!snap.hasData) return const Center(child: Text('No data available.'));

            final data = snap.data!;
            final isNarrow = MediaQuery.of(context).size.width < 380;

            // Top cards (weekly)
            final emittedCard = Expanded(
              child: _CardShell(
                child: _TopValueCard(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Carbon Emitted',
                  value: data.emittedKg,
                  color: const Color(0xFFD64545),
                ),
              ),
            );

            final savedCard = Expanded(
              child: _CardShell(
                child: _TopValueCard(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Carbon Saved',
                  value: data.savedKg.abs(),
                  color: const Color(0xFF2E7D32),
                ),
              ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StreakBarCard(streakDays: data.streakDays, carbonPoints: data.carbonPoints),
                  const SizedBox(height: 12),

                  if (isNarrow) ...[
                    emittedCard,
                    const SizedBox(height: 12),
                    savedCard,
                  ] else
                    Row(children: [emittedCard, const SizedBox(width: 12), savedCard]),

                  const SizedBox(height: 16),

                  // Conversions
                  _CardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(
                            icon: Icons.swap_horiz_rounded, label: 'CO₂ Conversions (Monthly)'),
                        const SizedBox(height: 8),
                        _ConversionGrid(emissionsKg: data.totalDisplayKg, metrics: data.metrics),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Separate charts (from EVENTS; with more spacing & clear axes)
                  _CardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(icon: Icons.bar_chart, label: 'Carbon Emitted (Weekly)'),
                        const SizedBox(height: 8),
                        MonthlyBarChart(
                          values: data.weeklyEmitted,        // red bars
                          labels: data.weekLabels,
                          barColor: const Color(0xFFD64545),
                        ),
                        const SizedBox(height: 28),
                        const _SectionHeader(icon: Icons.bar_chart, label: 'Carbon Saved (Weekly)'),
                        const SizedBox(height: 8),
                        MonthlyBarChart(
                          values: data.weeklySaved,          // green bars (magnitudes)
                          labels: data.weekLabels,
                          barColor: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Events
                  _CardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(icon: Icons.event_note_rounded, label: 'Recent Events'),
                        const SizedBox(height: 8),
                        _EventsTable(events: data.events),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/* ====================== View Models / UI Bits ====================== */

class _DashData {
  final double emittedKg;           // weekly (backend; may fallback to last 7 days)
  final double savedKg;             // weekly (backend; negative; displayed abs)
  final double totalDisplayKg;      // monthly net magnitude for conversions

  final List<double> weeklyNet;     // (kept) signed monthly weekly buckets (unused for bars now)
  final List<double> weeklyEmitted; // NEW: weekly bars from events (current month)
  final List<double> weeklySaved;   // NEW: weekly bars (magnitudes) from events
  final List<String> weekLabels;    // W1..W5

  final List<_Metric> metrics;
  final List<EventDto> events;

  final int streakDays;
  final int carbonPoints;

  _DashData({
    required this.emittedKg,
    required this.savedKg,
    required this.totalDisplayKg,
    required this.weeklyNet,
    required this.weeklyEmitted,
    required this.weeklySaved,
    required this.weekLabels,
    required this.metrics,
    required this.events,
    required this.streakDays,
    required this.carbonPoints,
  });
}

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

/* ====================== Streak Bar ====================== */

class _StreakBarCard extends StatelessWidget {
  final int streakDays;
  final int carbonPoints;
  const _StreakBarCard({required this.streakDays, required this.carbonPoints});

  @override
  Widget build(BuildContext context) {
    const cycle = 7;
    final inCycle = streakDays == 0 ? 0 : (streakDays % cycle);
    final filled = inCycle == 0 && streakDays > 0 ? cycle : inCycle;
    final remaining = (filled == cycle) ? 0 : (cycle - filled);

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Colors.deepOrange),
              const SizedBox(width: 8),
              const Text('Daily Streak',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer()
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 28,
            child: Row(
              children: List.generate(7, (i) {
                final isFilled = i < filled;
                final isFirst = i == 0;
                final isLast = i == 6;

                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(left: isFirst ? 0 : 6),
                    decoration: BoxDecoration(
                      color: isFilled ? const Color(0xFFFFC107) : const Color(0xFFFFF1B7),
                      borderRadius: BorderRadius.horizontal(
                        left: isFirst ? const Radius.circular(12) : Radius.zero,
                        right: isLast ? const Radius.circular(12) : Radius.zero,
                      ),
                      border: Border.all(
                        color: isFilled ? const Color(0xFFE7B006) : const Color(0xFFEFD787),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          // New: chip on first line, status on next line
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, // or .stretch + Align(...) if you want right-align
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: filled == 7 ? const Color(0xFF2E7D32) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: filled == 7 ? const Color(0xFF1B5E20) : const Color(0xFFB2DFDB),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      filled == 7 ? Icons.emoji_events : Icons.emoji_events_outlined,
                      size: 18,
                      color: filled == 7 ? Colors.white : const Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      filled == 7 ? 'Reward: +100 pts' : 'Reward at 7 days: +100 pts',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: filled == 7 ? Colors.white : const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // ⬇️ This is now on the next line
              Text(
                filled == 7
                    ? 'Great job! 🎉'
                    : (remaining == 1 ? '1 day to next reward' : '$remaining days to next reward'),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/* ====================== Events Table ====================== */

class _EventsTable extends StatelessWidget {
  final List<EventDto> events;
  const _EventsTable({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No events yet. Complete a quest to see it here.'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE6E8EC)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              color: const Color(0xFFF7F9FA),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: const Row(
                children: [
                  Expanded(flex: 6, child: Text('Description', style: TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(flex: 3, child: Text('CO₂e (kg)', style: TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(flex: 4, child: Text('Date', style: TextStyle(fontWeight: FontWeight.w700))),
                ],
              ),
            ),
            ...events.map((e) {
              final kg = e.emissions;
              final kgStr = kg.toStringAsFixed(3);
              final date = _fmtDate(e.datetime);
              return Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE6E8EC), width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: Text(e.description)),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Icon(
                            kg >= 0 ? Icons.north_rounded : Icons.south_rounded,
                            size: 16,
                            color: kg >= 0 ? const Color(0xFFD64545) : const Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            kgStr,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: kg >= 0 ? const Color(0xFFD64545) : const Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(flex: 4, child: Text(date, textAlign: TextAlign.right)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) => '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';
}

/* ====================== Conversions ====================== */

enum _CalcType { userOverEmissionsPerX, electricityTimesEmissionsPerX }

class _Metric {
  final int id;
  final String name;
  final String description;
  final double? emissionsPerX;
  final _CalcType calculation;
  final String unitLabel;
  final IconData icon;
  final double Function(double emissionsKg, _Metric metric)? overrideCompute;
  final String Function(double value) sentence;
  final Timeframe timeframe;

  _Metric({
    required this.id,
    required this.name,
    required this.description,
    required this.emissionsPerX,
    required this.calculation,
    required this.unitLabel,
    required this.icon,
    required this.sentence,
    this.overrideCompute,
    this.timeframe = Timeframe.day,
  });

  double? compute(double userEmissionsKg) {
    if (overrideCompute != null) return overrideCompute!(userEmissionsKg, this);
    switch (calculation) {
      case _CalcType.userOverEmissionsPerX:
        if (emissionsPerX == null || emissionsPerX == 0) return null;
        return userEmissionsKg / emissionsPerX!.abs();
      case _CalcType.electricityTimesEmissionsPerX:
        if (emissionsPerX == null) return null;
        return userEmissionsKg * emissionsPerX!;
    }
  }
}

/* === Compact Conversions Grid === */
class _ConversionGrid extends StatelessWidget {
  final double emissionsKg;
  final List<_Metric> metrics;

  const _ConversionGrid({required this.emissionsKg, required this.metrics});

  Color _iconBgFor(IconData icon) {
    if (icon == Icons.park_rounded) return const Color(0xFFE8F5E9);
    if (icon == Icons.bolt_rounded) return const Color(0xFFFFF3C4);
    if (icon == Icons.lightbulb_outline_rounded) return const Color(0xFFFFF8E1);
    if (icon == Icons.smartphone_rounded) return const Color(0xFFE3F2FD);
    if (icon == Icons.directions_car_rounded) return const Color(0xFFEDE7F6);
    return const Color(0xFFF1F3F4);
  }

  Color _iconFgFor(IconData icon) {
    if (icon == Icons.park_rounded) return const Color(0xFF2E7D32);
    if (icon == Icons.bolt_rounded) return const Color(0xFFFFC107);
    if (icon == Icons.lightbulb_outline_rounded) return const Color(0xFFF57F17);
    if (icon == Icons.smartphone_rounded) return const Color(0xFF1976D2);
    if (icon == Icons.directions_car_rounded) return const Color(0xFF5E35B1);
    return const Color(0xFF546E7A);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width > 760 ? 3 : 2;
    final tileHeight = width > 760 ? 160.0 : 190.0;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: tileHeight,
      ),
      itemBuilder: (context, i) {
        final m = metrics[i];
        final val = m.compute(emissionsKg);
        final sentence = (val == null) ? '—' : m.sentence(val);

        final bg = _iconBgFor(m.icon);
        final fg = _iconFgFor(m.icon);

        return Material(
          color: Colors.white,
          elevation: 0,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E8EC)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(m.icon, color: fg, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 2,
                          softWrap: true,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          sentence,
                          softWrap: true,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black87, height: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/* ====================== MonthlyBarChart (separate) ====================== */

class MonthlyBarChart extends StatelessWidget {
  final List<double> values; // positive-only for each chart
  final List<String> labels;
  final Color barColor;

  const MonthlyBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: CustomPaint(
        painter: _BarPainter(values: values, labels: labels, color: barColor),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  _BarPainter({required this.values, required this.labels, required this.color});

  final double _leftPad = 72; // extra spacing to prevent crowding
  final double _rightPad = 16;
  final double _topPad = 18;
  final double _bottomPad = 48; // more space for x labels

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _leftPad,
      _topPad,
      size.width - _leftPad - _rightPad,
      size.height - _topPad - _bottomPad,
    );

    // Axis/grid
    final axisPaint = Paint()..color = Colors.grey.shade400..strokeWidth = 1.2;
    final gridPaint = Paint()..color = Colors.grey.shade300..strokeWidth = 1;

    // Scales
    final maxVal = (values.isEmpty ? 10.0 : values.reduce(math.max));
    final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.25;
    const yTicks = 4;

    double yFor(double v) => rect.bottom - (v / maxY) * rect.height;

    // Grid + labels
    TextPainter _tp(String s) => TextPainter(
      text: TextSpan(text: s, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i <= yTicks; i++) {
      final t = i / yTicks;
      final y = rect.bottom - t * rect.height;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);

      final lbl = (maxY * t).toStringAsFixed(1);
      final tp = _tp(lbl)..layout();
      tp.paint(canvas, Offset(_leftPad - tp.width - 12, y - tp.height / 2));
    }

    // Axes
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, axisPaint);
    canvas.drawLine(rect.bottomLeft, rect.topLeft, axisPaint);

    // Bars
    if (values.isNotEmpty) {
      final count = values.length;
      final slot = rect.width / count;
      final barW = slot * 0.6;

      for (int i = 0; i < count; i++) {
        final v = values[i].clamp(0.0, maxY).toDouble();
        final y = yFor(v);
        final xc = rect.left + (i + 0.5) * slot;

        final r = Rect.fromLTWH(xc - barW / 2, y, barW, rect.bottom - y);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(6)),
          Paint()..color = color,
        );

        if (i < labels.length) {
          final tp = _tp(labels[i])..layout(maxWidth: slot);
          tp.paint(canvas, Offset(xc - tp.width / 2, rect.bottom + 8));
        }
      }
    }

    // Y axis title, pushed further left so it doesn't clash
    final yLab = TextPainter(
      text: const TextSpan(
        text: 'CO₂e (kg)',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(22, rect.center.dy + yLab.width / 2);
    canvas.rotate(-math.pi / 2);
    yLab.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) {
    return values != old.values || labels != old.labels || color != old.color;
  }
}

/* ====================== Helpers ====================== */

String _formatNumber(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  if (v >= 100) return v.toStringAsFixed(0);
  if (v >= 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

String _pad2(int n) => n < 10 ? '0$n' : '$n';
String _fmtDate(DateTime dt) => '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';

// Make receipt filename pretty if that’s what the scanner gave us.
String _prettifyReceiptDesc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Grocery receipt';
  var s = raw.trim();

  final parts = s.split(RegExp(r'[\/\\]+'));
  s = parts.isNotEmpty ? parts.last : s;

  s = s.replaceAll(RegExp(r'\.(png|jpg|jpeg|pdf|heic|webp)$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  if (s.isNotEmpty) s = s[0].toUpperCase() + (s.length > 1 ? s.substring(1) : '');
  if (s.isEmpty) return 'Grocery receipt';
  return 'Receipt: $s';
}

/* ====================== Small top value card ====================== */

class _TopValueCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  const _TopValueCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: icon, label: label),
        const SizedBox(height: 8),
        FittedBox(
          alignment: Alignment.bottomLeft,
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
