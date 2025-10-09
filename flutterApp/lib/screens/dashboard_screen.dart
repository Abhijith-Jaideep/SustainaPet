// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import '../api/base_url.dart';
import '../api/pawprint_api.dart';

// If you already have a Timeframe elsewhere, remove this.
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
    // 1) Fetch dashboard to get the user weekly counters (as-is)
    final dash = await api.getDashboard(uid);
    final user = dash.user;

    // 2) Fetch monthly data for chart + conversions
    final monthly = await api.getMonthlyEmissions(userid: uid);
    final conversions = await api.getConversions();
    final events = await api.getUserEvents(uid, limit: 25);

    // ===== Read & consume "pending" receipt emissions (set by grocery scanner) =====
    // NOTE: This only affects monthly visuals (chart/conversions), not the weekly cards.
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getDouble('pending_receipt_emissions_$uid') ?? 0.0;
    final pendingDesc = prefs.getString('pending_receipt_desc');
    final pendingTsStr = prefs.getString('pending_receipt_ts');
    final pendingTs = pendingTsStr != null
        ? DateTime.tryParse(pendingTsStr) ?? DateTime.now()
        : DateTime.now();

    // Chart data (monthly weekly buckets; signed values +/-)
    final weeklySorted = [...monthly.weekly]..sort((a, b) => a.week.compareTo(b.week));
    final weeklyNet = weeklySorted.map((w) => w.kg).toList();
    final weekLabels = weeklySorted.map((w) => 'W${w.week}').toList();

    // === TOP CARDS (weekly): display exactly what backend sends ===
    final emittedWeekly = user.weeklyEmissionsProduced; // e.g., 0.0
    final savedWeekly = user.weeklyEmissionsSaved; // e.g., -2.55

    // Conversions use monthly net (absolute magnitude)
    double adjustedNet = monthly.netKg;

    // Apply pending ONLY to monthly visuals
    if (pending.abs() > 1e-9) {
      if (weeklyNet.isNotEmpty) {
        weeklyNet[weeklyNet.length - 1] = weeklyNet.last + pending;
      }
      adjustedNet += pending;

      events.insert(
        0,
        EventDto(
          eventid: 0,
          userid: uid,
          userquestid: null,
          description: pendingDesc ?? 'Grocery receipt',
          type: 'Receipt',
          emissions: pending,
          datetime: pendingTs,
        ),
      );

      await prefs.remove('pending_receipt_emissions_$uid');
      await prefs.remove('pending_receipt_desc');
      await prefs.remove('pending_receipt_ts');
    }

    final totalDisplayKg = adjustedNet.abs();

    // ----- Build conversions (with icons per metric) -----
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

    const kgPerKwh = 0.7; // example factor
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

    return _DashData(
      emittedKg: emittedWeekly, // weekly_emissions_produced (as-is)
      savedKg: savedWeekly, // weekly_emissions_saved (as-is; may be negative)
      totalDisplayKg: totalDisplayKg, // abs(monthly net) for conversions
      weeklyNet: weeklyNet, // monthly chart (with pending bump if any)
      weekLabels: weekLabels,
      metrics: metrics,
      events: events,
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
                    Text('Failed to load dashboard:\n${snap.error}', textAlign: TextAlign.center),
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

            // Build the two top cards once so we can reuse for Row/Column layout.
            final emittedCard = Expanded(
              child: _CardShell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Carbon Emitted',
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        alignment: Alignment.bottomLeft,
                        fit: BoxFit.scaleDown,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              data.emittedKg.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFD64545),
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
                    ),
                  ],
                ),
              ),
            );

            final savedCard = Expanded(
              child: _CardShell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(
                      icon: Icons.arrow_downward_rounded,
                      label: 'Carbon Saved',
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        alignment: Alignment.bottomLeft,
                        fit: BoxFit.scaleDown,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Show as positive for nicer UI, underlying value may be negative.
                            Text(
                              data.savedKg.abs().toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2E7D32),
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
                    ),
                  ],
                ),
              ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // === Top row: Carbon Emitted + Carbon Saved (WEEKLY) ===
                  if (isNarrow) ...[
                    emittedCard,
                    const SizedBox(height: 12),
                    savedCard,
                  ] else
                    Row(
                      children: [
                        emittedCard,
                        const SizedBox(width: 12),
                        savedCard,
                      ],
                    ),

                  const SizedBox(height: 16),

                  // === Compact CO₂ Conversions Grid (MONTHLY) ===
                  _CardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(
                          icon: Icons.swap_horiz_rounded,
                          label: 'CO₂ Conversions (Monthly)',
                        ),
                        const SizedBox(height: 8),
                        _ConversionGrid(
                          emissionsKg: data.totalDisplayKg,
                          metrics: data.metrics,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // === Monthly Emissions Chart (with axes) ===
                  _CardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(
                          icon: Icons.bar_chart_rounded,
                          label: 'Monthly CO₂ Emissions',
                        ),
                        const SizedBox(height: 8),
                        MonthlyEmissionsChart(
                          values: data.weeklyNet, // +/- weekly kg
                          labels: data.weekLabels, // ["W1","W2",...]
                          yTicks: 4,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Weekly net CO₂e (kg). Red = emitted, Green = saved.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // === Events table ===
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
  // weekly, shown as-is in top cards
  final double emittedKg; // weekly_emissions_produced
  final double savedKg; // weekly_emissions_saved (may be negative)
  // monthly visuals
  final double totalDisplayKg; // abs(monthly net) for conversions
  final List<double> weeklyNet; // monthly weekly buckets (signed)
  final List<String> weekLabels;
  final List<_Metric> metrics;
  final List<EventDto> events;

  _DashData({
    required this.emittedKg,
    required this.savedKg,
    required this.totalDisplayKg,
    required this.weeklyNet,
    required this.weekLabels,
    required this.metrics,
    required this.events,
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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

    final emitted = events.where((e) => e.emissions > 0).toList();
    final saved = events.where((e) => e.emissions <= 0).toList();

    final totalEmitted = emitted.fold<double>(0, (sum, e) => sum + e.emissions);
    final totalSaved = saved.fold<double>(0, (sum, e) => sum + e.emissions.abs());

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE6E8EC)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              color: const Color(0xFFF7F9FA),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: const Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Text(
                      'Description',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'CO₂e (kg)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Date',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            // Summary Row
            Container(
              color: const Color(0xFFFFC107),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    flex: 6,
                    child: Text(
                      'Summary',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emitted: ${totalEmitted.toStringAsFixed(2)} kg',
                          style: const TextStyle(
                            color: Color(0xFFD64545),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Saved: ${totalSaved.toStringAsFixed(2)} kg',
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(flex: 4, child: SizedBox()),
                ],
              ),
            ),

            // Rows
            ...events.map((e) {
              final kg = e.emissions;
              final kgStr = kg.toStringAsFixed(3);
              final date = _fmtDate(e.datetime);

              return Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFE6E8EC), width: 1),
                  ),
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
                            kg <= 0 ? Icons.south_rounded : Icons.north_rounded,
                            size: 16,
                            color: kg <= 0 ? const Color(0xFF2E7D32) : const Color(0xFFD64545),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            kgStr,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: kg <= 0 ? const Color(0xFF2E7D32) : const Color(0xFFD64545),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        date,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';
  }
}

/* ====================== Conversions ====================== */

enum _CalcType { userOverEmissionsPerX, electricityTimesEmissionsPerX }

class _Metric {
  final int id;
  final String name;
  final String description;
  final double? emissionsPerX; // negative in DB for savings; use abs() for math
  final _CalcType calculation;
  final String unitLabel;
  final IconData icon; // metric-specific icon
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
    this.timeframe = Timeframe.day, // default
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

/* === Compact Conversions Grid with metric-specific icons === */
class _ConversionGrid extends StatelessWidget {
  final double emissionsKg;
  final List<_Metric> metrics;

  const _ConversionGrid({
    required this.emissionsKg,
    required this.metrics,
  });

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
    // 2 columns on phones, 3 on wider screens
    final width = MediaQuery.of(context).size.width;
    final cols = width > 760 ? 3 : 2;

    final tileHeight = width > 760 ? 160.0 : 190.0; // taller tiles so text never clips

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: tileHeight, // key: taller tiles
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
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(m.icon, color: fg, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title (allow up to 2 lines, wrap)
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 2,
                          softWrap: true,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Sentence: wrap fully, no ellipses
                      Flexible(
                        child: Text(
                          sentence,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            height: 1.2,
                          ),
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

/* ====================== Proper Monthly Emissions Chart ====================== */

class MonthlyEmissionsChart extends StatelessWidget {
  final List<double> values; // e.g., [-1.2, 0.8, -0.3, 1.0, 0.0]
  final List<String> labels; // e.g., ["W1","W2","W3","W4","W5"]
  final int yTicks;

  const MonthlyEmissionsChart({
    super.key,
    required this.values,
    required this.labels,
    this.yTicks = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: CustomPaint(
            painter: _MonthlyBarPainter(
              values: values,
              labels: labels,
              maxAbsY: _niceMaxAbs(values),
              yTicks: yTicks,
              axisColor: Colors.grey.shade400,
              gridColor: Colors.grey.shade300,
              posBarColor: const Color(0xFFE74C3C), // red for +kg
              negBarColor: const Color(0xFF2E7D32), // green for -kg (savings)
              labelStyle: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Weeks',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

double _niceMaxAbs(List<double> vals) {
  if (vals.isEmpty) return 10.0;
  final maxAbs = vals.map((v) => v.abs()).fold<double>(0.0, (p, e) => e > p ? e : p);
  if (maxAbs == 0) return 10.0;
  double nice = 1.0;
  while (nice < maxAbs) nice *= 2;
  return nice;
}

class _MonthlyBarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final double maxAbsY;
  final int yTicks;

  final Color axisColor;
  final Color gridColor;
  final Color posBarColor;
  final Color negBarColor;
  final TextStyle labelStyle;

  _MonthlyBarPainter({
    required this.values,
    required this.labels,
    required this.maxAbsY,
    required this.yTicks,
    required this.axisColor,
    required this.gridColor,
    required this.posBarColor,
    required this.negBarColor,
    required this.labelStyle,
  });

  final double _leftPad = 48;
  final double _rightPad = 12;
  final double _topPad = 16;
  final double _bottomPad = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(
      _leftPad,
      _topPad,
      size.width - _leftPad - _rightPad,
      size.height - _topPad - _bottomPad,
    );

    final paintGrid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final paintAxis = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;

    final tp = (String s) => TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );

    // Y grid + labels (+max ... -max)
    for (int i = 0; i <= yTicks; i++) {
      final t = i / yTicks; // 0..1
      final yValue = maxAbsY - (2 * maxAbsY) * t; // +max..-max
      final y = chartRect.top + t * chartRect.height;

      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), paintGrid);

      final lbl = yValue.toStringAsFixed(1);
      final tpLbl = tp(lbl)..layout();
      tpLbl.paint(canvas, Offset(_leftPad - 6 - tpLbl.width, y - tpLbl.height / 2));
    }

    // Y-axis title
    final yTitle = TextPainter(
      text: TextSpan(
        text: 'CO₂e (kg)',
        style: labelStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(12, chartRect.center.dy + yTitle.width / 2);
    canvas.rotate(-math.pi / 2);
    yTitle.paint(canvas, Offset.zero);
    canvas.restore();

    // Axes
    canvas.drawLine(chartRect.topLeft, chartRect.bottomLeft, paintAxis);
    canvas.drawLine(chartRect.bottomLeft, chartRect.bottomRight, paintAxis);

    double yFor(double value) {
      final t = (maxAbsY - value) / (2 * maxAbsY); // 0..1
      return chartRect.top + t * chartRect.height;
    }

    // Zero line
    final zeroY = yFor(0);
    if (zeroY >= chartRect.top && zeroY <= chartRect.bottom) {
      final zeroPaint = Paint()
        ..color = axisColor.withOpacity(0.9)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(chartRect.left, zeroY), Offset(chartRect.right, zeroY), zeroPaint);
    }

    // Bars
    if (values.isEmpty) return;
    final count = values.length;
    final barSlot = chartRect.width / count;
    final barWidth = barSlot * 0.6;

    for (int i = 0; i < count; i++) {
      final v = values[i].clamp(-maxAbsY, maxAbsY);
      final isPos = v >= 0;
      final color = isPos ? posBarColor : negBarColor;

      final xCenter = chartRect.left + (i + 0.5) * barSlot;
      final xLeft = xCenter - barWidth / 2;
      final yValue = yFor(v);
      final yZero = yFor(0);

      final rect = Rect.fromLTRB(
        xLeft,
        isPos ? yValue : yZero,
        xLeft + barWidth,
        isPos ? yZero : yValue,
      );

      final rPaint = Paint()..color = color;
      final rR = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rR, rPaint);

      if (i < labels.length) {
        final t = TextPainter(
          text: TextSpan(text: labels[i], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: barSlot);
        t.paint(canvas, Offset(xCenter - t.width / 2, chartRect.bottom + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyBarPainter oldDelegate) {
    return values != oldDelegate.values ||
        labels != oldDelegate.labels ||
        maxAbsY != oldDelegate.maxAbsY ||
        yTicks != oldDelegate.yTicks;
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
String _fmtDateTime(DateTime dt) {
  final d = dt.toLocal();
  final y = d.year;
  final m = _pad2(d.month);
  final day = _pad2(d.day);
  final hh = _pad2(d.hour);
  final mm = _pad2(d.minute);
  return '$y-$m-$day $hh:$mm';
}
