import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/utils/snackbar_x.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';
import 'package:nousmind/widgets/image_preview_screen.dart';
import 'package:nousmind/widgets/inspiration_list_item.dart';

/// Home screen for the inspirations tab: shows all inspirations, hosts the
/// FAB to add a new one, and routes taps to the editor and left-swipes to
/// delete.
class InspirationsHomePage extends StatefulWidget {
  const InspirationsHomePage({super.key});

  @override
  State<InspirationsHomePage> createState() => _InspirationsHomePageState();
}

class _InspirationsHomePageState extends State<InspirationsHomePage> {
  DateTimeRange? _selectedDateRange;

  Future<void> _selectDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _selectedDateRange,
    );
    if (range != null) {
      setState(() {
        _selectedDateRange = range;
      });
    }
  }

  Widget _buildFilterBar() {
    final colors = Theme.of(context).colorScheme;
    final startStr =
        '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}';
    final endStr =
        '${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Icon(Icons.date_range_outlined, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '日期筛选: $startStr 至 $endStr',
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _selectedDateRange = null),
            tooltip: '清除筛选',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => _showSearch(context),
          ),
          IconButton(
            icon: Icon(
              Icons.calendar_month_outlined,
              color: _selectedDateRange != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: '按日期筛选',
            onPressed: _selectDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 智能分析',
            onPressed: () => context.push('/inspirations/ai'),
          ),
        ],
      ),
      body: Consumer<InspirationsViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          var items = viewModel.inspirations;
          if (_selectedDateRange != null) {
            final start = DateUtils.dateOnly(_selectedDateRange!.start);
            final end = DateUtils.dateOnly(
              _selectedDateRange!.end,
            ).add(const Duration(days: 1));
            items = items
                .where(
                  (i) =>
                      i.createdAt.isAfter(start) && i.createdAt.isBefore(end),
                )
                .toList();
          }

          if (items.isEmpty) {
            if (_selectedDateRange != null) {
              return Column(
                children: [
                  _buildFilterBar(),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EmptyState(
                            icon: Icons.calendar_today_outlined,
                            title: '该时间段内没有灵感',
                            subtitle: '尝试选择其他日期范围或清除筛选',
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () =>
                                setState(() => _selectedDateRange = null),
                            child: const Text('清除筛选'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return const EmptyState(
              icon: Icons.lightbulb_outline,
              title: '还没有灵感',
              subtitle: '点击右下角 + 记录一条',
            );
          }

          return Column(
            children: [
              if (_selectedDateRange != null) _buildFilterBar(),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final inspiration = items[index];
                    return InspirationListItem(
                      inspiration: inspiration,
                      onTap: () => _openEditor(context, inspiration),
                      onImageTap: (i) => _openImagePreview(context, i),
                      onDelete: () =>
                          _deleteWithFeedback(context, viewModel, inspiration),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'inspirations-fab',
        onPressed: () => _openEditor(context, null),
        tooltip: '添加灵感',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSearch(BuildContext context) {
    final viewModel = context.read<InspirationsViewModel>();
    showSearch(
      context: context,
      delegate: _InspirationSearchDelegate(
        viewModel: viewModel,
        onTap: (inspiration) {
          context.push('/inspirations/editor', extra: inspiration);
        },
        onImageTap: (inspiration) => _openImagePreview(context, inspiration),
        onDelete: (inspiration) {
          _deleteWithFeedback(context, viewModel, inspiration);
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, Inspiration? existing) async {
    await context.push('/inspirations/editor', extra: existing);
  }

  void _openImagePreview(BuildContext context, Inspiration inspiration) {
    final path = inspiration.imagePath;
    if (path == null) return;
    Navigator.of(context, rootNavigator: true).push(
      openImagePreviewRoute(
        imagePath: path,
        heroTag: 'inspiration-thumb:${inspiration.id}',
      ),
    );
  }

  Future<void> _deleteWithFeedback(
    BuildContext context,
    InspirationsViewModel viewModel,
    Inspiration inspiration,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await viewModel.delete(inspiration.id);
    final text = inspiration.text;
    final displayTitle = text.length > 15
        ? '${text.substring(0, 15)}...'
        : text;
    messenger.showAppSnackBar(
      '已移入回收站「$displayTitle」',
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () => viewModel.restore(inspiration.id),
      ),
    );
  }
}

class _InspirationSearchDelegate extends SearchDelegate<String> {
  _InspirationSearchDelegate({
    required this.viewModel,
    required this.onTap,
    required this.onDelete,
    this.onImageTap,
  });

  final InspirationsViewModel viewModel;
  final void Function(Inspiration) onTap;
  final void Function(Inspiration) onDelete;
  final void Function(Inspiration)? onImageTap;

  @override
  String get searchFieldLabel => '搜索灵感...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = viewModel.inspirations
        .where(
          (i) =>
              i.text.toLowerCase().contains(query.toLowerCase()) ||
              (i.ocrText != null &&
                  i.ocrText!.toLowerCase().contains(query.toLowerCase())),
        )
        .toList();
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '没有匹配结果',
        subtitle: '换个关键词试试',
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final inspiration = results[index];
        return InspirationListItem(
          inspiration: inspiration,
          onTap: () {
            close(context, inspiration.id);
            onTap(inspiration);
          },
          onImageTap: onImageTap,
          onDelete: () => onDelete(inspiration),
        );
      },
    );
  }
}
