// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import '../api/base_url.dart';
import '../api/pawprint_api.dart';
// NOTE: removed '../model/timeframe.dart' to avoid duplicate enum conflicts

enum Timeframe {
  day,
  week,
  month,
}

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
      if (uid != null) await prefs.setInt('userId', uid); // migrate
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
    final base = pickBaseUrl();
    api = PawprintApi(base);
    _initializeDashboard();
  }

  Future<_DashData> _load(int uid) async {
    final monthly = await api.getMonthlyEmissions(userid: uid);
    final conversions = await api.getConversions();
    final events = await api.getUserEvents(uid, limit: 25); // recent events

    final totalDisplayKg = monthly.netKg.abs();

    // Sort weeks and keep signed values
    final weeklySorted = [...monthly.weekly]..sort((a, b) => a.week.compareTo(b.week));
    final weeklyNet = weeklySorted.map((w) => w.kg).toList();
    final weekLabels = weeklySorted.map((w) => 'W${w.week}').toList();

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
        // tutor asked for time-specific phrasing (just text)
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

    return _DashData(
      totalDisplayKg: totalDisplayKg,
      weeklyNet: weeklyNet,
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
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // === Top row: Carbon Emitted + Carbon Saved ===
                  Row(
                    children: [
                      Expanded(
                        child: _CardShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.arrow_upward_rounded,
                                label: 'Carbon Emitted',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    data.weeklyNet
                                        .where((v) => v > 0)
                                        .fold(0.0, (a, b) => a + b)
                                        .toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFD64545), // red
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'kg',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CardShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.arrow_downward_rounded,
                                label: 'Carbon Saved',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    data.weeklyNet
                                        .where((v) => v < 0)
                                        .fold(0.0, (a, b) => a + b)
                                        .abs()
                                        .toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E7D32), // green
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'kg',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // === Compact CO₂ Conversions Grid ===
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
                        const _SectionHeader(icon: Icons.bar_chart_rounded, label: 'Monthly CO₂ Emissions'),
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
  final double totalDisplayKg;
  final List<double> weeklyNet; // signed values
  final List<String> weekLabels;
  final List<_Metric> metrics;
  final List<EventDto> events;

  _DashData({
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
              child: Row(
                children: const [
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
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/* ====================== Conversions ====================== */

enum _CalcType { userOverEmissionsPerX, electricityTimesEmissionsPerX }

class _Metric {
  final int id;
  final String name;
  final String description;
  final double? emissionsPerX; // negative in DB for savings; use abs() in math
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

/* === Compact Conversions Grid (replaces _ConversionList in UI) === */
class _ConversionGrid extends StatelessWidget {
  final double emissionsKg;
  final List<_Metric> metrics;

  const _ConversionGrid({
    required this.emissionsKg,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    // 2 columns on phones, 3 on wider screens
    final width = MediaQuery.of(context).size.width;
    final cols = width > 760 ? 3 : 2;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // ↓ Give each tile a bit more height (fixes "BOTTOM OVERFLOWED" by ~6-8px)
        childAspectRatio: 2.0,
      ),
      itemBuilder: (context, i) {
        final m = metrics[i];
        final val = m.compute(emissionsKg);
        final sentence = (val == null) ? '—' : m.sentence(val);

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
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF3C4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.eco_rounded, color: Color(0xFFFFC107), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title (1 line)
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13, // a hair smaller helps on tight tiles
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Sentence (up to 2 lines)
                      Text(
                        sentence,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black87,
                          height: 1.15, // slightly tighter leading
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

    for (int i = 0; i <= yTicks; i++) {
      final t = i / yTicks; // 0..1
      final yValue = maxAbsY - (2 * maxAbsY) * t; // +max..-max
      final y = chartRect.top + t * chartRect.height;

      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), paintGrid);

      final lbl = yValue.toStringAsFixed(1);
      final tpLbl = tp(lbl)..layout();
      tpLbl.paint(canvas, Offset(_leftPad - 6 - tpLbl.width, y - tpLbl.height / 2));
    }

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

    canvas.drawLine(chartRect.topLeft, chartRect.bottomLeft, paintAxis);
    canvas.drawLine(chartRect.bottomLeft, chartRect.bottomRight, paintAxis);

    double yFor(double value) {
      final t = (maxAbsY - value) / (2 * maxAbsY); // 0..1
      return chartRect.top + t * chartRect.height;
    }

    final zeroY = yFor(0);
    if (zeroY >= chartRect.top && zeroY <= chartRect.bottom) {
      final zeroPaint = Paint()
        ..color = axisColor.withOpacity(0.9)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(chartRect.left, zeroY), Offset(chartRect.right, zeroY), zeroPaint);
    }

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


// // lib/screens/dashboard_screen.dart
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
//
// class EventDto {
//   final String description;
//   final double emissions;
//   final DateTime datetime;
//
//   EventDto({
//     required this.description,
//     required this.emissions,
//     required this.datetime,
//   });
// }
//
// class DashboardScreen extends StatefulWidget {
//   const DashboardScreen({super.key});
//
//   @override
//   _DashboardScreenState createState() => _DashboardScreenState();
// }
//
// class _DashboardScreenState extends State<DashboardScreen> {
//   late Future<_DashData> _future;
//
//   @override
//   void initState() {
//     super.initState();
//     _future = _loadData();
//   }
//
//   Future<_DashData> _loadData() async {
//     await Future.delayed(const Duration(seconds: 1));
//     // 模拟每周净排放数据
//     final weeklyNet = [2.0, -1.0, 3.0, -2.5, 1.0, -0.5];
//     return _DashData(
//       totalDisplayKg: weeklyNet.fold(0, (a, b) => a + b),
//       weeklyNet: weeklyNet,
//       weekLabels: ["W1","W2","W3","W4","W5","W6"],
//       metrics: [
//         _Metric(name: "Trees", value: 10),
//         _Metric(name: "kWh", value: 200),
//       ],
//       events: [
//         EventDto(description: "Bike ride", emissions: -1.0, datetime: DateTime.now().subtract(const Duration(days: 1))),
//         EventDto(description: "Car commute", emissions: 2.5, datetime: DateTime.now().subtract(const Duration(days: 2))),
//       ],
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Dashboard")),
//       body: FutureBuilder<_DashData>(
//         future: _future,
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           } else if (snapshot.hasError) {
//             return Center(child: Text("Error: ${snapshot.error}"));
//           } else if (!snapshot.hasData) {
//             return const Center(child: Text("No data"));
//           }
//
//           final data = snapshot.data!;
//
//           return SingleChildScrollView(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 // === Carbon Metrics 分成两类 ===
//                 Text('Carbon Emitted: ${data.emitted.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 14)),
//                 Text('Carbon Saved: ${data.saved.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 14)),
//                 const SizedBox(height: 16),
//
//                 // === Metrics 显示 Monthly + 名称 ===
//                 Column(
//                   children: data.metrics.map((m) => _MetricWidget(metric: m)).toList(),
//                 ),
//                 const SizedBox(height: 16),
//
//                 // === Monthly Emissions Chart ===
//                 MonthlyEmissionsChart(values: data.weeklyNet),
//
//                 const SizedBox(height: 16),
//                 // === Recent Events (只显示日期) ===
//                 const Text("Recent Activities", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
//                 const SizedBox(height: 8),
//                 Column(
//                   children: data.events.map((e) {
//                     final dateStr = "${e.datetime.year}-${_pad2(e.datetime.month)}-${_pad2(e.datetime.day)}";
//                     return ListTile(
//                       title: Text(e.description),
//                       trailing: Text(dateStr),
//                       leading: Icon(
//                         e.emissions >= 0 ? Icons.north_rounded : Icons.south_rounded,
//                         color: e.emissions >= 0 ? Colors.red : Colors.green,
//                       ),
//                     );
//                   }).toList(),
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }
// }
//
// class _DashData {
//   final double totalDisplayKg;
//   final List<double> weeklyNet;
//   final List<String> weekLabels;
//   final List<_Metric> metrics;
//   final List<EventDto> events;
//
//   _DashData({
//     required this.totalDisplayKg,
//     required this.weeklyNet,
//     required this.weekLabels,
//     required this.metrics,
//     required this.events,
//   });
//
//   double get emitted => weeklyNet.where((v) => v > 0).fold(0.0, (a, b) => a + b);
//   double get saved => weeklyNet.where((v) => v < 0).fold(0.0, (a, b) => a + b).abs();
// }
//
// class _Metric {
//   final String name;
//   final double value;
//   _Metric({required this.name, required this.value});
// }
//
// class _MetricWidget extends StatelessWidget {
//   final _Metric metric;
//   const _MetricWidget({required this.metric});
//
//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       margin: const EdgeInsets.symmetric(vertical: 6),
//       child: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(
//           children: [
//             Text('${metric.name} (Monthly)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
//             const SizedBox(height: 6),
//             Text(metric.value.toString(), style: const TextStyle(fontSize: 20)),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// class MonthlyEmissionsChart extends StatelessWidget {
//   final List<double> values;
//   const MonthlyEmissionsChart({super.key, required this.values});
//
//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       height: 250,
//       child: BarChart(
//         BarChartData(
//           alignment: BarChartAlignment.spaceAround,
//           maxY: values.isEmpty ? 10 : values.reduce((a,b)=>a>b?a:b) + 5,
//           barGroups: List.generate(values.length, (i) {
//             return BarChartGroupData(
//               x: i,
//               barRods: [
//                 BarChartRodData(toY: values[i], color: values[i]>=0?Colors.red:Colors.green),
//               ],
//             );
//           }),
//           titlesData: FlTitlesData(
//             bottomTitles: AxisTitles(
//               sideTitles: SideTitles(
//                 showTitles: true,
//                 getTitlesWidget: (value, _) => Text('M${value.toInt() + 1}'),
//               ),
//             ),
//             leftTitles: AxisTitles(
//               sideTitles: SideTitles(showTitles: true, reservedSize: 28),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// // Helper
// String _pad2(int n) => n < 10 ? '0$n' : '$n';
//
//
//
//
// /* ====================== 下面是原来的 UI 组件和帮助函数，保持不变 ====================== */
//
// // 省略重复的 _DashData、_CardShell、_SectionHeader、_EventsTable、_Metric、_ConversionList、MonthlyEmissionsChart、_MonthlyBarPainter、_formatNumber、_fmtDate 等代码
// // 可直接复用你原来的实现
