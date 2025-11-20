import 'package:flutter/material.dart';
import 'today.dart';
import 'nutrient.dart';
import 'goal.dart';
import 'calendar.dart';
import 'diary.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  final _tabs = const [
    TodayPage(),
    NutrientPage(),
    GoalPage(),
    CalendarPage(),
    DiaryPage(),
  ];

  void _goTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final headerH = screenW * 146 / 1080; // Top.png is 1080x146
    final barH    = screenW * 226 / 1080; // Bottom.png is 1080x226

    return Scaffold(
      // top header image
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(headerH),
        child: AppBar(
          elevation: 0,
          toolbarHeight: 0,
          backgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          flexibleSpace: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/Top.png',
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  width: screenW,
                  height: headerH,
                ),
                // profile button (same look)
                Positioned(
                  right: 12,
                  top: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/profile'),
                    child: Image.asset('assets/icons/Profile.png', width: 48, height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      body: IndexedStack(index: _index, children: _tabs),

      // bottom image + NavigationBar overlay
      bottomNavigationBar: SizedBox(
        height: barH,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/images/Bottom.png',
                  fit: BoxFit.fitWidth, alignment: Alignment.topCenter),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: NavigationBarTheme(
                data: const NavigationBarThemeData(
                  backgroundColor: Colors.transparent,
                  indicatorColor: Color(0xFFE6DEFF),
                  height: 72,
                  elevation: 0,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _goTab,
                    destinations: const [
                      NavigationDestination(
                        icon: _NavIcon('assets/icons/task.png'),
                        selectedIcon: _NavIcon('assets/icons/task.png'),
                        label: 'Task',
                      ),
                      NavigationDestination(
                        icon: _NavIcon('assets/icons/Nutrients.png'),
                        selectedIcon: _NavIcon('assets/icons/Nutrients.png'),
                        label: 'Nutrient',
                      ),
                      NavigationDestination(
                        icon: _NavIcon('assets/icons/Goal.png'),
                        selectedIcon: _NavIcon('assets/icons/Goal.png'),
                        label: 'Goal',
                      ),
                      NavigationDestination(
                        icon: _NavIcon('assets/icons/Calendar.png'),
                        selectedIcon: _NavIcon('assets/icons/Calendar.png'),
                        label: 'Calendar',
                      ),
                      NavigationDestination(
                        icon: _NavIcon('assets/icons/Diary.png'),
                        selectedIcon: _NavIcon('assets/icons/Diary.png'),
                        label: 'Diary',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final String path;
  const _NavIcon(this.path);
  @override
  Widget build(BuildContext context) =>
      Image.asset(path, width: 28, height: 28);
}
