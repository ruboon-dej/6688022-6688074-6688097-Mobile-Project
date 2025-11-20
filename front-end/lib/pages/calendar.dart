// lib/pages/calendar.dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../config.dart';       // you still need this for other pages
import 'task_sync.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;

  /// key = 'YYYY-MM-DD', value = list of tasks due that day
  Map<String, List<Map<String, dynamic>>> _eventsByDate = {};
  bool _loading = false;

  late final VoidCallback _taskListener;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(_focused.year, _focused.month, _focused.day);

    _taskListener = () {
      _rebuildFromTasks();
    };
    TaskSync.version.addListener(_taskListener);

    _rebuildFromTasks();
  }

  @override
  void dispose() {
    TaskSync.version.removeListener(_taskListener);
    super.dispose();
  }

  // ==== helpers (same as TodayPage) ========================================

  bool _isDone(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }

  DateTime? _parseDue(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, "0")}-'
      '${d.month.toString().padLeft(2, "0")}-'
      '${d.day.toString().padLeft(2, "0")}';

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Color _dot(int urgency) {
    switch (urgency) {
      case 1:
        return const Color(0xFFD33F43); // red
      case 2:
        return const Color(0xFFF4A63B); // orange
      default:
        return const Color(0xFF66BB6A); // green
    }
  }

  // ==== build from TaskSync.tasks ==========================================

  void _rebuildFromTasks() {
    setState(() => _loading = true);

    final list = TaskSync.tasks;
    final byDate = <String, List<Map<String, dynamic>>>{};

    for (final t in list) {
      if (_isDone(t['done'])) continue;
      final due = _parseDue(t['due_date']);
      if (due == null) continue;

      final key = _fmtDate(due);
      (byDate[key] ??= []).add(t);
    }

    setState(() {
      _eventsByDate = byDate;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = _fmtDate(DateTime(day.year, day.month, day.day));
    return _eventsByDate[key] ?? const [];
  }

  // ==== UI ================================================================

  @override
  Widget build(BuildContext context) {
    final selectedDay = _selected ?? _focused;
    final selectedEvents = _getEventsForDay(selectedDay);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Calendar',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TableCalendar<Map<String, dynamic>>(
                  firstDay: DateTime.utc(2000, 1, 1),
                  lastDay: DateTime.utc(2100, 12, 31),
                  focusedDay: _focused,
                  selectedDayPredicate: (d) =>
                      _selected != null && isSameDay(_selected, d),
                  onDaySelected: (sel, foc) {
                    setState(() {
                      _selected = sel;
                      _focused = foc;
                    });
                  },
                  onPageChanged: (newFocused) {
                    _focused = newFocused;
                  },
                  eventLoader: (day) => _getEventsForDay(day),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  calendarStyle: const CalendarStyle(
                    isTodayHighlighted: true,
                    outsideDaysVisible: false,
                  ),
                  availableGestures: AvailableGestures.horizontalSwipe,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: selectedEvents.isEmpty
                        ? const Center(
                            child: Text('No tasks due on this day'),
                          )
                        : ListView.separated(
                            itemCount: selectedEvents.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final t = selectedEvents[i];
                              final title = (t['title'] ?? '').toString();
                              final urgency = _toInt(t['urgency']) ?? 1;

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: _dot(urgency),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
