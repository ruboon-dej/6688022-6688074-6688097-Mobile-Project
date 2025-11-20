// lib/pages/task_sync.dart
import 'package:flutter/foundation.dart';

/// Global place to keep tasks in memory and notify listeners when they change.
class TaskSync {
  /// Bumps whenever the task list changes.
  /// CalendarPage / GoalPage listen to this.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// Optional in-memory copy of tasks (if any page wants to read them).
  static List<Map<String, dynamic>> tasks = [];

  /// Replace the global task list and notify listeners (like CalendarPage/GoalPage).
  static void setTasks(List<Map<String, dynamic>> newTasks) {
    tasks = List<Map<String, dynamic>>.from(newTasks);
    version.value++;
  }

  /// Simple "bump" if you changed tasks but didn't call setTasks.
  /// (Not strictly needed, but keeps old code that used notifyChanged working.)
  static void notifyChanged() {
    version.value++;
  }
}
