import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/stats_provider.dart';
import '../models/stat_entry.dart';
import 'home_screen.dart';

enum _Period { daily, weekly, monthly }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with WidgetsBindingObserver {
  _Period _period = _Period.daily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatsProvider>().load();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<StatsProvider>().load();
    }
  }

  DateTimeRange _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _Period.daily:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case _Period.weekly:
        return DateTimeRange(start: today.subtract(const Duration(days: 27)), end: today);
      case _Period.monthly:
        return DateTimeRange(start: DateTime(now.year, now.month - 2, 1), end: today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<StatsProvider>();
    final range = _range();

    if (stats.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6B9E78))),
      );
    }

    final dailies = stats.dailyTotals(range.start, range.end);
    final appTotals = stats.appTotals(range.start, range.end);

    final totalIntercepted = appTotals.fold(0, (s, a) => s + a.intercepted);
    final totalSummarised = appTotals.fold(0, (s, a) => s + a.summarised);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6B9E78),
        onRefresh: stats.load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 600;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: wide ? constraints.maxWidth * 0.1 : 16,
                vertical: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Period selector ───────────────────────────────────────
                  _PeriodSelector(
                    current: _period,
                    onChanged: (p) => setState(() => _period = p),
                  ),
                  const SizedBox(height: 16),

                  // ── Totals summary row ────────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: _StatCard(
                        label: 'Intercepted',
                        value: '$totalIntercepted',
                        icon: Icons.notifications_outlined,
                        color: const Color(0xFF4A90D9),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(
                        label: 'Summarised',
                        value: '$totalSummarised',
                        icon: Icons.auto_awesome_outlined,
                        color: const Color(0xFF6B9E78),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(
                        label: 'Saved',
                        value: totalIntercepted == 0
                            ? '0%'
                            : '${((totalSummarised / totalIntercepted) * 100).round()}%',
                        icon: Icons.timer_outlined,
                        color: const Color(0xFFE8A838),
                      )),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Bar chart ─────────────────────────────────────────────
                  if (dailies.isNotEmpty) ...[
                    _SectionLabel('Trend'),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _buildChart(dailies),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LegendDot(color: const Color(0xFF4A90D9), label: 'Intercepted'),
                        const SizedBox(width: 20),
                        _LegendDot(color: const Color(0xFF6B9E78), label: 'Summarised'), // Note: softWrap handles this
                      ],
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.bar_chart, size: 48, color: Colors.white24),
                          SizedBox(height: 12),
                          Text('No data yet',
                              style: TextStyle(color: Colors.white38, fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Stats will appear once notifications are being summarised',
                              style: TextStyle(color: Colors.white24, fontSize: 12),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Per-app breakdown ─────────────────────────────────────
                  if (appTotals.isNotEmpty) ...[
                    _SectionLabel('By app'),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        children: [
                          // Header row
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: const [
                                Expanded(flex: 3, child: Text('App',
                                    style: TextStyle(color: Colors.white38,
                                        fontSize: 12, fontWeight: FontWeight.w600))),
                                Expanded(child: Text('Seen',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Color(0xFF4A90D9),
                                        fontSize: 12, fontWeight: FontWeight.w600))),
                                Expanded(child: Text('Summarised',
                                    textAlign: TextAlign.center,
                                    softWrap: false,
                                    style: TextStyle(color: Color(0xFF6B9E78),
                                        fontSize: 12, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          ...appTotals.asMap().entries.map((entry) {
                            final i = entry.key;
                            final app = entry.value;
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            _AppAvatar(app.packageName),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(app.appName,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 14)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Text('${app.intercepted}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Color(0xFF4A90D9),
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      Expanded(
                                        child: Text('${app.summarised}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Color(0xFF6B9E78),
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (i < appTotals.length - 1)
                                  const Divider(color: Colors.white10, height: 1),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChart(List<DailyTotal> dailies) {
    final maxVal = dailies.fold<double>(0, (m, d) => d.intercepted > m ? d.intercepted.toDouble() : m);

    return BarChart(
      BarChartData(
        maxY: maxVal == 0 ? 5 : maxVal * 1.3,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2A2A2A),
            getTooltipItem: (group, gi, rod, ri) {
              final d = dailies[group.x];
              return BarTooltipItem(
                '${_shortDate(d.date)}\n',
                const TextStyle(color: Colors.white, fontSize: 12),
                children: [
                  TextSpan(
                    text: ri == 0
                        ? 'Intercepted: ${d.intercepted}'
                        : 'Summarised: ${d.summarised}',
                    style: TextStyle(
                      color: ri == 0 ? const Color(0xFF4A90D9) : const Color(0xFF6B9E78),
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= dailies.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_shortDate(dailies[i].date),
                      style: const TextStyle(color: Colors.white38, fontSize: 9)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text('${v.toInt()}',
                  style: const TextStyle(color: Colors.white24, fontSize: 9)),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Colors.white10, strokeWidth: 1),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        barGroups: dailies.asMap().entries.map((e) {
          final i = e.key;
          final d = e.value;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: d.intercepted.toDouble(),
                color: const Color(0xFF4A90D9),
                width: 6,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
              BarChartRodData(
                toY: d.summarised.toDouble(),
                color: const Color(0xFF6B9E78),
                width: 6,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  String _shortDate(String date) {
    try {
      final d = DateTime.parse(date);
      return DateFormat('d/M').format(d);
    } catch (_) {
      return date;
    }
  }
}

class _PeriodSelector extends StatelessWidget {
  final _Period current;
  final void Function(_Period) onChanged;
  const _PeriodSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: _Period.values.map((p) {
          final selected = p == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF4A7A56) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  p.name[0].toUpperCase() + p.name.substring(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white38,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF6B9E78), fontSize: 13,
                fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12), softWrap: false, overflow: TextOverflow.ellipsis),
        ],
      );
}

class _AppAvatar extends StatelessWidget {
  final String packageName;
  const _AppAvatar(this.packageName);
  @override
  Widget build(BuildContext context) {
    final letter = packageName.split('.').lastWhere((s) => s.isNotEmpty, orElse: () => 'A')[0].toUpperCase();
    const colors = [Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0), Color(0xFFFF5722), Color(0xFF00BCD4)];
    return Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        color: colors[packageName.hashCode.abs() % colors.length],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(letter,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
    );
  }
}
