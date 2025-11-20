// lib/pages/today_page.dart
import 'package:flutter/material.dart';
import '../config.dart';
import 'task_sync.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      final data = await apiGet('/tasks'); // [{id,title,urgency,due_date,done,...}]
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(data);
      setState(() {
        _tasks = list;
        _loading = false;
      });
      // update global TaskSync + notify listeners (Goal, Calendar)
      TaskSync.setTasks(list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---- helpers ----------------------------------------------------

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

  String _fmtDate(DateTime? d) =>
      d == null
          ? 'No due date'
          : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

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

  List<Map<String, dynamic>> get _visibleTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Show: NOT done AND (no due date OR due >= today)
    final filtered = _tasks.where((t) {
      final notDone = !_isDone(t['done']);
      final due = _parseDue(t['due_date']);
      final show = due == null || !due.isBefore(today);
      return notDone && show;
    }).toList();

    // Sort by due date (null last), then urgency
    filtered.sort((a, b) {
      final da = _parseDue(a['due_date']);
      final db = _parseDue(b['due_date']);
      if (da == null && db == null) {
        final ua = (a['urgency'] ?? 3) as int;
        final ub = (b['urgency'] ?? 3) as int;
        return ua.compareTo(ub);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      final ua = (a['urgency'] ?? 3) as int;
      final ub = (b['urgency'] ?? 3) as int;
      return ua.compareTo(ub);
    });

    return filtered;
  }

  // ---- mark as done / undone --------------------------------------

  Future<void> _setDone(Map<String, dynamic> task, bool done) async {
    final id = task['id'];
    if (id == null) return;

    try {
      await apiPut('/tasks/$id', {
        'done': done ? 1 : 0,
      });
      await _loadTasks(); // refresh + TaskSync.setTasks() inside
    } catch (_) {
      // optional: show error Snackbar
    }
  }

  // ---- dialogs ----------------------------------------------------

  Future<void> _openMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Task'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'add'),
            child: const Text('Add'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: const Text('Remove'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == 'add') {
      await _addTaskDialog();
    } else if (choice == 'remove') {
      await _removeTaskDialog();
    }
  }

  Future<void> _addTaskDialog() async {
    final titleCtrl = TextEditingController();
    int urgency = 1;
    DateTime? due;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: urgency,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Urgency: High (red)')),
                  DropdownMenuItem(
                    value: 2,
                    child: Text('Urgency: Medium (orange)'),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text('Urgency: Low (green)'),
                  ),
                ],
                onChanged: (v) => setLocal(() => urgency = v ?? 1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Due date:'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      due == null ? 'No due date' : _fmtDate(due),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: due ?? now,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked != null) setLocal(() => due = picked);
                    },
                    child: const Text('Pick'),
                  ),
                  if (due != null)
                    TextButton(
                      onPressed: () => setLocal(() => due = null),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      final body = {
        'title': titleCtrl.text.trim(),
        'urgency': urgency,
        'due_date': due == null ? null : _fmtDate(due),
        'done': 0,
      };
      await apiPost('/tasks', body);
      await _loadTasks(); // refresh + TaskSync.setTasks() inside
    }
  }

  Future<void> _removeTaskDialog() async {
    final selected = <int>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Remove Tasks'),
          content: SizedBox(
            width: 360,
            height: 300,
            child: _tasks.isEmpty
                ? const Center(child: Text('No tasks'))
                : ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (_, i) {
                      final t = _tasks[i];
                      final id = t['id'] as int;
                      return CheckboxListTile(
                        value: selected.contains(id),
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                          });
                        },
                        title: Text((t['title'] ?? '').toString()),
                        subtitle: Text(_fmtDate(_parseDue(t['due_date']))),
                        secondary: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _dot((t['urgency'] ?? 1) as int),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && selected.isNotEmpty) {
      for (final id in selected) {
        try {
          await apiDelete('/tasks/$id');
        } catch (_) {}
      }
      await _loadTasks(); // refresh + TaskSync.setTasks() inside
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleTasks;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _loadTasks,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Text(
                  'Today',
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
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: Text('No tasks')),
              )
            else
              for (final t in items) ...[
                _TaskTile(
                  title: (t['title'] ?? '').toString(),
                  dueText: _fmtDate(_parseDue(t['due_date'])),
                  urgencyColor: _dot((t['urgency'] ?? 1) as int),
                  done: _isDone(t['done']),
                  onChangedDone: (v) => _setDone(t, v ?? false),
                ),
                const SizedBox(height: 16),
              ],
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final String title;
  final String dueText;
  final Color urgencyColor;
  final bool done;
  final ValueChanged<bool?> onChangedDone;

  const _TaskTile({
    required this.title,
    required this.dueText,
    required this.urgencyColor,
    required this.done,
    required this.onChangedDone,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 800 / 300,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/TaskBox.png', fit: BoxFit.fill),
          ),
          Positioned.fill(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Checkbox(
                    value: done,
                    onChanged: onChangedDone,
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: urgencyColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dueText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
