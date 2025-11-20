// lib/pages/goal.dart
import 'package:flutter/material.dart';
import '../config.dart';
import 'task_sync.dart';

class GoalPage extends StatefulWidget {
  const GoalPage({super.key});

  @override
  State<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<GoalPage> {
  double progress = 0.0; // 0.0 .. 1.0
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initLoad();
    // Listen for task changes (from TodayPage, Calendar, etc.)
    TaskSync.version.addListener(_onTasksChanged);
  }

  @override
  void dispose() {
    TaskSync.version.removeListener(_onTasksChanged);
    super.dispose();
  }

  // -------- helpers ----------

  bool _isDone(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }

  void _onTasksChanged() {
    // TaskSync.tasks was updated somewhere -> recompute progress from cache
    _computeFromCache();
  }

  Future<void> _initLoad() async {
    // First time: if TaskSync already has tasks, just use them.
    // If empty (user opens Goal first), load from backend once.
    if (TaskSync.tasks.isEmpty) {
      await _loadFromBackend();
    } else {
      _computeFromCache();
    }
  }

  Future<void> _loadFromBackend() async {
    setState(() => _loading = true);
    try {
      final data = await apiGet('/tasks'); // [{id,title,urgency,due_date,done,...}]
      final list = List<Map<String, dynamic>>.from(data);

      // Save globally + notify listeners (Calendar, Goal, etc.)
      TaskSync.setTasks(list);

      // We will also compute locally (though _onTasksChanged will run too)
      _computeFromList(list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _computeFromCache() {
    _computeFromList(TaskSync.tasks);
  }

  void _computeFromList(List<Map<String, dynamic>> list) {
    setState(() => _loading = true);

    int total = list.length;
    int done = 0;
    for (final t in list) {
      if (_isDone(t['done'])) done++;
    }

    final p = total == 0 ? 0.0 : done / total;

    if (!mounted) return;
    setState(() {
      progress = p.clamp(0.0, 1.0);
      _loading = false;
    });
  }

  Future<void> _openMenu() async {
    // Just explain how this page works (user cannot edit progress directly)
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('How is this goal calculated?'),
        content: const Text(
          'The circle shows what percent of your tasks are completed.\n\n'
          'progress = (number of completed tasks) ÷ (total number of tasks).\n\n'
          'To change it, add / delete tasks or mark them as done on the Task page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct = (progress.clamp(0.0, 1.0) * 100).round();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(
                  'Goal',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openMenu,
                  child: Image.asset(
                    'assets/icons/Pencil.png',
                    width: 26,
                    height: 26,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: _RingPainter(progress),
                  child: Center(
                    child: Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'You have completed $pct% of your tasks',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Finish or delete tasks to change this number.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double p;
  _RingPainter(this.p);

  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero);
    final r = s.shortestSide * 0.38;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = const Color(0xFF181818).withOpacity(0.08);

    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4B7FD3);

    // background ring
    c.drawCircle(center, r, base);

    // progress arc
    final start = -90 * 3.1415926535 / 180;
    final sweep = (p.clamp(0.0, 1.0)) * 2 * 3.1415926535;
    c.drawArc(
      Rect.fromCircle(center: center, radius: r),
      start,
      sweep,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p;
}
