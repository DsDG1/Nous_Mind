import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../viewmodels/reminders_view_model.dart';
import '../widgets/create_reminder_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/reminder_list_item.dart';

/// Home screen: shows all reminders, hosts the FAB to add a new one, and
/// routes taps to the editor and left-swipes to delete.
class RemindersHomePage extends StatefulWidget {
  const RemindersHomePage({super.key});

  @override
  State<RemindersHomePage> createState() => _RemindersHomePageState();
}

class _RemindersHomePageState extends State<RemindersHomePage> {
  final GlobalKey _fabKey = GlobalKey();

  Future<void> _openEditor(BuildContext context, Reminder? existing) async {
    final fabRenderBox =
        _fabKey.currentContext?.findRenderObject() as RenderBox?;
    final fabPosition = fabRenderBox != null
        ? fabRenderBox.localToGlobal(
            Offset(fabRenderBox.size.width / 2, fabRenderBox.size.height / 2),
          )
        : Offset.zero;
    await context.push('/editor', extra: (existing, fabPosition));
  }

  Future<void> _openCreateChooser(BuildContext context) async {
    final fabRenderBox =
        _fabKey.currentContext?.findRenderObject() as RenderBox?;
    final fabPosition = fabRenderBox != null
        ? fabRenderBox.localToGlobal(
            Offset(fabRenderBox.size.width / 2, fabRenderBox.size.height / 2),
          )
        : Offset.zero;
    await CreateReminderSheet.show(context, fabPosition: fabPosition);
  }

  Future<void> _deleteWithFeedback(
    BuildContext context,
    RemindersViewModel viewModel,
    Reminder reminder,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await viewModel.delete(reminder.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已删除「${reminder.title}」'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒事项')),
      body: Consumer<RemindersViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = viewModel.reminders;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: '还没有提醒',
              subtitle: '点击右下角 + 添加',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final reminder = items[index];
              return ReminderListItem(
                reminder: reminder,
                onTap: () => _openEditor(context, reminder),
                onDelete: () =>
                    _deleteWithFeedback(context, viewModel, reminder),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: _fabKey,
        onPressed: () => _openCreateChooser(context),
        tooltip: '添加提醒',
        child: const Icon(Icons.add),
      ),
    );
  }
}
