// lib/pages/diary.dart
import 'package:flutter/material.dart';
import '../config.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});
  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  DateTime day = DateTime.now();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDiary();
  }

  Future<void> _loadDiary() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final d = day.toIso8601String().substring(0, 10);
    try {
      final data = await apiGet('/diary', {'date': d});
      if (!mounted) return;
      setState(() {
        _entries = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Diary'),
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
      await _addDiaryDialog();
    } else if (choice == 'remove') {
      await _removeDiaryDialog();
    }
  }

  Future<void> _addDiaryDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Diary'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Title (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: 'Content'),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final title = titleCtrl.text.trim();
    final content = contentCtrl.text.trim();

    if (ok == true && (title.isNotEmpty || content.isNotEmpty)) {
      final d = day.toIso8601String().substring(0, 10);
      await apiPost('/diary', {
        'date': d,
        'title': title,
        'content': content,
      });
      await _loadDiary();
    }
  }

  // ✅ FIXED DELETE DIALOG
  Future<void> _removeDiaryDialog() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No entries to remove.')),
      );
      return;
    }

    final selected = <int>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            int getId(Map<String, dynamic> e) {
              final raw = e['id'];
              if (raw is int) return raw;
              if (raw is num) return raw.toInt();
              return int.tryParse(raw.toString()) ?? -1;
            }

            return AlertDialog(
              title: const Text('Remove Diary Entries'),
              content: SizedBox(
                width: 360,
                height: 300,
                child: ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final e = _entries[i];
                    final id = getId(e);

                    return CheckboxListTile(
                      value: selected.contains(id),
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        });
                      },
                      title: Text(_entryTitle(e)),
                      subtitle: Text(
                        _entrySubtitle(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || selected.isEmpty) return;

    // Optimistic UI update first
    setState(() {
      _entries.removeWhere((e) {
        final raw = e['id'];
        final id = (raw is num)
            ? raw.toInt()
            : int.tryParse(raw.toString()) ?? -1;
        return selected.contains(id);
      });
    });

    // Call backend deletes
    int failCount = 0;
    for (final id in selected) {
      try {
        await apiDelete('/diary/$id');
      } catch (_) {
        failCount++;
      }
    }

    if (!mounted) return;

    if (failCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed for $failCount item(s).')),
      );
    }

    await _loadDiary(); // final sync
  }

  // ========= helpers to format entry text =========

  String _entryTitle(Map<String, dynamic> e) {
    final t = (e['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;

    final raw = (e['content'] ?? e['text'] ?? '').toString();
    if (raw.trim().isEmpty) return '(Untitled)';
    final i = raw.indexOf('\n');
    return i < 0 ? raw : raw.substring(0, i);
  }

  String _entrySubtitle(Map<String, dynamic> e) {
    final raw = (e['content'] ?? e['text'] ?? '').toString();
    final i = raw.indexOf('\n');
    return i < 0 ? '' : raw.substring(i + 1);
  }

  String _entryBody(Map<String, dynamic> e) {
    final content = (e['content'] ?? e['text'] ?? '').toString();
    return content;
  }

  Future<void> _viewEntry(Map<String, dynamic> e) async {
    final title = _entryTitle(e);
    final body = _entryBody(e);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(
            body.isEmpty ? '(No content)' : body,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  'Diary',
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
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_entries.isEmpty
                    ? const Center(child: Text('No diary entries today'))
                    : ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final e = _entries[i];
                          return ListTile(
                            tileColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(
                              _entryTitle(e),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _entrySubtitle(e),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _viewEntry(e),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }
}
