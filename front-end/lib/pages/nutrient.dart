// lib/pages/nutrient.dart
import 'package:flutter/material.dart';
import '../config.dart'; // ApiException, apiGet/apiPost/apiPut/apiDelete

class NutrientPage extends StatefulWidget {
  const NutrientPage({super.key});

  @override
  State<NutrientPage> createState() => _NutrientPageState();
}

class _NutrientPageState extends State<NutrientPage> {
  // current (computed from history by backend)
  double curVeg = 0, curCarb = 0, curProtein = 0;

  // goal
  double goalVeg = 0, goalCarb = 0, goalProtein = 0;

  bool _loading = true;

  // history list (latest first)
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;

  // for today (extend later)
  String? _dateISO;

  // colors
  static const _cVeg = Color(0xFF66BB6A);
  static const _cCarb = Color(0xFF42A5F5);
  static const _cProt = Color(0xFFFF7043);
  static const _cGray = Color(0xFFE0E0E0);

  static const double _maxGram = 1000000;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadNutrients(), _loadHistory()]);
  }

  Future<void> _loadNutrients() async {
    setState(() => _loading = true);
    try {
      final q = _dateISO != null ? {'date': _dateISO!} : null;
      final data = await apiGet('/nutrients', q);

      final c = Map<String, dynamic>.from(data['current'] ?? {});
      final g = Map<String, dynamic>.from(data['goal'] ?? {});
      if (!mounted) return;

      setState(() {
        curVeg = (c['veg'] ?? 0).toDouble();
        curCarb = (c['carb'] ?? 0).toDouble();
        curProtein = (c['protein'] ?? 0).toDouble();

        goalVeg = (g['veg'] ?? 0).toDouble();
        goalCarb = (g['carb'] ?? 0).toDouble();
        goalProtein = (g['protein'] ?? 0).toDouble();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final q = {'limit': '20', if (_dateISO != null) 'date': _dateISO!};
      final data = await apiGet('/nutrients/history', q);
      if (!mounted) return;

      setState(() {
        _history = List<Map<String, dynamic>>.from(data);
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  // ---------- Menus ----------
  Future<void> _openTopMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Nutrient'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'goal'),
            child: const Text('Edit goal'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == 'goal') await _openGoalDialog();
  }

  Future<void> _openHistoryMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('History'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'add'),
            child: const Text('Add food'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('Edit an item'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete items'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == 'add') {
      await _addHistoryDialog();
    } else if (choice == 'edit') {
      await _editOneHistoryDialog();
    } else if (choice == 'delete') {
      await _deleteHistoryDialog();
    }

    await _loadAll();
  }

  // ---------- Goal dialog (sum stays 100%) ----------
  Future<void> _openGoalDialog() async {
    double v = goalVeg, c = goalCarb, p = goalProtein;

    final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => StatefulBuilder(
            builder: (ctx, setLocal) {
              void fixTotal() {
                final sum = v + c + p;
                if (sum <= 1.0 || sum == 0) return;
                v = v / sum;
                c = c / sum;
                p = p / sum;
                setLocal(() {});
              }

              Widget bar() {
                final sum = (v + c + p).clamp(0.0, 1.0);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        Expanded(flex: (v * 1000).round(), child: Container(color: _cVeg)),
                        Expanded(flex: (c * 1000).round(), child: Container(color: _cCarb)),
                        Expanded(flex: (p * 1000).round(), child: Container(color: _cProt)),
                        if (sum < 1.0)
                          Expanded(
                            flex: ((1.0 - sum) * 1000).round(),
                            child: Container(color: _cGray),
                          ),
                      ],
                    ),
                  ),
                );
              }

              Widget coloredSlider({
                required double value,
                required ValueChanged<double> onChanged,
                required Color color,
                required String label,
                required String pct,
              }) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Text(label), const Spacer(), Text(pct)]),
                    SliderTheme(
                      data: SliderTheme.of(ctx).copyWith(
                        activeTrackColor: color,
                        inactiveTrackColor: _cGray.withOpacity(0.35),
                        thumbColor: color,
                        overlayColor: color.withOpacity(0.12),
                      ),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: 1,
                        divisions: 100,
                        onChanged: (x) {
                          onChanged(x);
                          fixTotal();
                        },
                      ),
                    ),
                  ],
                );
              }

              final totalOK = (v + c + p - 1.0).abs() < 1e-6;

              return AlertDialog(
                title: const Text('Set goal (must total 100%)'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      bar(),
                      const SizedBox(height: 16),
                      coloredSlider(
                        value: v,
                        onChanged: (x) => setLocal(() => v = x),
                        color: _cVeg,
                        label: 'Veg / Fruit',
                        pct: '${(v * 100).round()}%',
                      ),
                      coloredSlider(
                        value: c,
                        onChanged: (x) => setLocal(() => c = x),
                        color: _cCarb,
                        label: 'Carb',
                        pct: '${(c * 100).round()}%',
                      ),
                      coloredSlider(
                        value: p,
                        onChanged: (x) => setLocal(() => p = x),
                        color: _cProt,
                        label: 'Protein',
                        pct: '${(p * 100).round()}%',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: totalOK ? () => Navigator.pop(ctx, true) : null,
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;

    if (!ok) return;

    await apiPut('/nutrients/goal', {'veg': v, 'carb': c, 'protein': p});
    await _loadNutrients();
  }

  // ---------- History add ----------
  Future<void> _addHistoryDialog() async {
    final name = TextEditingController();
    final veg = TextEditingController();
    final carb = TextEditingController();
    final prot = TextEditingController();
    final amt = TextEditingController();

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Add food'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Food name')),
                  const SizedBox(height: 8),
                  TextField(controller: veg, decoration: const InputDecoration(labelText: 'veg_g (grams)'), keyboardType: TextInputType.number),
                  TextField(controller: carb, decoration: const InputDecoration(labelText: 'carb_g (grams)'), keyboardType: TextInputType.number),
                  TextField(controller: prot, decoration: const InputDecoration(labelText: 'protein_g (grams)'), keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  TextField(controller: amt, decoration: const InputDecoration(labelText: 'amount_g (optional)'), keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    final vegVal = double.tryParse(veg.text) ?? 0;
    final carbVal = double.tryParse(carb.text) ?? 0;
    final protVal = double.tryParse(prot.text) ?? 0;
    final amtVal = amt.text.trim().isEmpty ? null : double.tryParse(amt.text.trim());

    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a food name.')));
      return;
    }

    bool tooLarge(double v) => v.abs() > _maxGram;
    if (tooLarge(vegVal) || tooLarge(carbVal) || tooLarge(protVal) || (amtVal != null && tooLarge(amtVal))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Value too large (< 1,000,000 g).')));
      return;
    }

    try {
      await apiPost('/nutrients/history', {
        'name': name.text.trim(),
        'veg_g': vegVal,
        'carb_g': carbVal,
        'protein_g': protVal,
        'amount_g': amtVal,
      });
      await _loadAll();
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Server error: ${e.message}')));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unexpected error while adding.')));
    }
  }

  // ---------- History edit ----------
  Future<void> _editHistoryItem(Map<String, dynamic> item) async {
    final name = TextEditingController(text: (item['name'] ?? '').toString());
    final veg  = TextEditingController(text: '${item['veg_g'] ?? 0}');
    final carb = TextEditingController(text: '${item['carb_g'] ?? 0}');
    final prot = TextEditingController(text: '${item['protein_g'] ?? 0}');
    final amt  = TextEditingController(
      text: item['amount_g'] == null ? '' : '${item['amount_g']}',
    );

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Edit food'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Food name')),
                  const SizedBox(height: 8),
                  TextField(controller: veg, decoration: const InputDecoration(labelText: 'veg_g (grams)'), keyboardType: TextInputType.number),
                  TextField(controller: carb, decoration: const InputDecoration(labelText: 'carb_g (grams)'), keyboardType: TextInputType.number),
                  TextField(controller: prot, decoration: const InputDecoration(labelText: 'protein_g (grams)'), keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  TextField(controller: amt, decoration: const InputDecoration(labelText: 'amount_g (optional)'), keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    final vegVal  = double.tryParse(veg.text) ?? 0;
    final carbVal = double.tryParse(carb.text) ?? 0;
    final protVal = double.tryParse(prot.text) ?? 0;
    final amtVal  = amt.text.trim().isEmpty ? null : double.tryParse(amt.text.trim());

    bool tooLarge(double v) => v.abs() > _maxGram;
    if (tooLarge(vegVal) || tooLarge(carbVal) || tooLarge(protVal) || (amtVal != null && tooLarge(amtVal))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Value too large (< 1,000,000 g).')));
      return;
    }

    try {
      await apiPut('/nutrients/history/${item['id']}', {
        'name': name.text.trim(),
        'veg_g': vegVal,
        'carb_g': carbVal,
        'protein_g': protVal,
        'amount_g': amtVal,
      });
      await _loadAll();
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Server error: ${e.message}')));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unexpected error while editing.')));
    }
  }

  Future<void> _editOneHistoryDialog() async {
    if (_history.isEmpty) return;

    final choice = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pick an item to edit'),
        children: [
          for (int i = 0; i < _history.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Text((_history[i]['name'] ?? 'Food').toString()),
            ),
        ],
      ),
    );

    if (choice == null) return;
    await _editHistoryItem(_history[choice]);
  }

  // ---------- History delete (FIXED CHECKBOX UI) ----------
  Future<void> _deleteHistoryDialog() async {
    if (_history.isEmpty) return;
    final selected = <int>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete history'),
          content: SizedBox(
            width: 360,
            height: 320,
            child: ListView.builder(
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final h = _history[i];
                final id = h['id'] as int;
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
                  title: Text((h['name'] ?? 'Food').toString()),
                  subtitle: Text(
                    'veg ${h['veg_g']}g • carb ${h['carb_g']}g • protein ${h['protein_g']}g',
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (ok == true && selected.isNotEmpty) {
      for (final id in selected) {
        try {
          await apiDelete('/nutrients/history/$id');
        } catch (_) {}
      }
      await _loadAll();
    }
  }

  // ---------- Suggestions ----------
  List<String> _buildSuggestions() {
    if (_history.isEmpty) return const ['No data yet'];
    const th = 0.08;
    final difVeg = curVeg - goalVeg;
    final difCarb = curCarb - goalCarb;
    final difProt = curProtein - goalProtein;

    final out = <String>[];
    if (difVeg < -th) out.add('Eat more vegetables/fruit.');
    if (difCarb > th) out.add('Reduce carbohydrates.');
    if (difProt > th) out.add('Reduce protein portions.');
    if (out.isEmpty) out.add('Great balance today — keep it up!');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final currentSlices = _history.isEmpty
        ? [_Slice(1.0, _cGray, 'No data')]
        : [
            _Slice(curVeg, _cVeg, 'Veg/Fruit'),
            _Slice(curCarb, _cCarb, 'Carb'),
            _Slice(curProtein, _cProt, 'Protein'),
          ];

    final gsum = goalVeg + goalCarb + goalProtein;
    final goalSlices = (gsum <= 0)
        ? [_Slice(1.0, _cGray, 'Unset')]
        : [
            _Slice(goalVeg, _cVeg, 'Veg/Fruit'),
            _Slice(goalCarb, _cCarb, 'Carb'),
            _Slice(goalProtein, _cProt, 'Protein'),
          ];

    final suggestions = _buildSuggestions();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Nutrient',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _openTopMenu,
                    child: Image.asset('assets/icons/Pencil.png', width: 26, height: 26),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Row(
                  children: [
                    Expanded(child: _PieCard(title: 'today (from history)', slices: currentSlices)),
                    const SizedBox(width: 16),
                    Expanded(child: _PieCard(title: 'goal', slices: goalSlices)),
                  ],
                ),

              const SizedBox(height: 18),
              Text('Suggestion',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final s in suggestions)
                _SuggestionLine(text: s, color: const Color(0xFF33691E)),

              const SizedBox(height: 18),
              Row(
                children: [
                  Text('History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _openHistoryMenu,
                    child: Image.asset('assets/icons/Pencil.png', width: 22, height: 22),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_loadingHistory)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_history.isEmpty)
                const Text('No history yet')
              else
                Column(
                  children: [
                    for (final h in _history) ...[
                      _HistoryTile(
                        title: (h['name'] ?? 'Food').toString(),
                        subtitle: 'veg ${h['veg_g']}g • carb ${h['carb_g']}g • protein ${h['protein_g']}g',
                        onTap: () => _editHistoryItem(h), // TAP TO EDIT ✅
                      ),
                      const SizedBox(height: 10),
                    ]
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------ Pie & helpers ------------------ */

class _PieCard extends StatelessWidget {
  final String title;
  final List<_Slice> slices;

  const _PieCard({required this.title, required this.slices});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _PiePainter(slices)),
        ),
        const SizedBox(height: 6),
        Text(title,
            style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _Slice {
  final double f;
  final Color c;
  final String label;
  const _Slice(this.f, this.c, this.label);
}

class _PiePainter extends CustomPainter {
  final List<_Slice> slices;
  _PiePainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    double start = -90 * 3.1415926535 / 180;

    if (slices.length == 1) {
      paint.color = slices.first.c;
      canvas.drawArc(rect, start, 2 * 3.14159, true, paint);
    } else {
      for (final s in slices) {
        final sweep = (s.f.clamp(0.0, 1.0)) * 2 * 3.1415926535;
        paint.color = s.c;
        canvas.drawArc(rect, start, sweep, true, paint);
        start += sweep;
      }
    }

    final hole = Paint()..color = Colors.white;
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.32, hole);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) => oldDelegate.slices != slices;
}

class _SuggestionLine extends StatelessWidget {
  final String text;
  final Color color;
  const _SuggestionLine({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: TextStyle(fontSize: 16, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _HistoryTile({required this.title, this.subtitle, this.onTap});

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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0C0C0C))),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}
