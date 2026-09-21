import 'dart:convert';

import 'package:flutter/material.dart';
import '../../Models/CourseTableModel.dart';
import '../../Models/PersonalSchedule.dart';
import '../../Utils/States/MainState.dart';
import 'Widgets/AddDialog.dart';

class ManageTableView extends StatefulWidget {
  const ManageTableView({super.key});
  @override
  State<ManageTableView> createState() => _ManageTableViewState();
}

class _ManageTableViewState extends State<ManageTableView> {
  final _provider = CourseTableProvider();
  late Future<List> _tables = _provider.getAllCourseTable();
  bool _busy = false;

  void _error() {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作未完成，请重试。')));
    }
  }

  Future<void> _select(int id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MainStateModel.of(context).changeclassTable(id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const AddDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final current = await loadPersonalSchedule();
      // Share the current semester and clock periods, not the source import identity.
      final table = await _provider.insert(
        CourseTable(
          name.trim(),
          data: jsonEncode({
            'semester_start_monday': current.firstMonday
                .toIso8601String()
                .split('T')
                .first,
            'class_time_list': current.periods,
          }),
        ),
      );
      if (!mounted) return;
      await MainStateModel.of(context).changeclassTable(table.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${table['name']}”？'),
        content: const Text('将删除这份课表及其中课程。当前使用的课表不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _provider.delete(table['id'] as int);
      if (mounted) setState(() => _tables = _provider.getAllCourseTable());
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('课表管理'),
      actions: [
        IconButton(
          tooltip: '新增课表',
          icon: const Icon(Icons.add),
          onPressed: _busy ? null : _add,
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<List>(
        future: _tables,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _tables = _provider.getAllCourseTable()),
                child: const Text('读取失败，点击重试'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<int>(
            future: MainStateModel.of(context).getClassTable(),
            builder: (context, selected) => ListView(
              children: [
                if (_busy) const LinearProgressIndicator(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('点击课表即可切换。新增课表沿用当前学期和作息。'),
                ),
                for (final table in snapshot.data!)
                  ListTile(
                    title: Text(table['name']),
                    selected: selected.data == table['id'],
                    subtitle: selected.data == table['id']
                        ? const Text('当前课表')
                        : null,
                    onTap: _busy ? null : () => _select(table['id'] as int),
                    trailing: selected.data == table['id']
                        ? const SizedBox.square(
                            dimension: 48,
                            child: Center(child: Icon(Icons.check_rounded)),
                          )
                        : IconButton(
                            tooltip: '删除${table['name']}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : () => _delete(table),
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
