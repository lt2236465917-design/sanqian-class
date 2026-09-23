import '../../Components/ScheduleDesign.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  late Future<List> _tables = _loadTables();
  int? _selectedId, _selectingId;
  bool _busy = false;
  bool get _locked => _busy || _selectingId != null;

  Future<List> _loadTables() async {
    final tables = await _provider.getAllCourseTable();
    _selectedId =
        (await SharedPreferences.getInstance()).getInt('tableId') ?? 0;
    return tables;
  }

  Future<bool> _rename(int id, String name) async {
    if (_locked) return false;
    setState(() => _busy = true);
    try {
      await _provider.rename(id, name);
      if (mounted) {
        setState(() => _tables = _loadTables());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课表名称已保存')));
      }
      return true;
    } catch (_) {
      _error();
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error() {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作未完成，请重试。')));
    }
  }

  Future<void> _select(int id) async {
    if (_locked || id == _selectedId) return;
    setState(() => _selectingId = id);
    try {
      await MainStateModel.of(context).changeclassTable(id);
      if (mounted) setState(() => _selectedId = id);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _selectingId = null);
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
      if (mounted) setState(() => _tables = _loadTables());
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
          onPressed: _locked ? null : _add,
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
                onPressed: () => setState(() => _tables = _loadTables()),
                child: const Text('读取失败，点击重试'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                height: 4,
                child: _locked ? const LinearProgressIndicator() : null,
              ),
              const ScheduleIntro(
                icon: Icons.calendar_month_outlined,
                eyebrow: '学期与课程',
                title: '每份课表，各自有序',
                description: '点击名称框切换课表，也可直接修改名称。当前使用的课表会显示对勾。',
              ),
              const SizedBox(height: 24),
              for (final table in snapshot.data!)
                Padding(
                  key: ValueKey(table['id']),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _TableNameField(
                          key: ValueKey(table['id']),
                          name: table['name'] as String,
                          enabled:
                              !_busy &&
                              (_selectingId == null ||
                                  _selectingId == table['id']),
                          current: _selectedId == table['id'],
                          onSelect: () => _select(table['id'] as int),
                          onSave: (name) => _rename(table['id'] as int, name),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_selectedId == table['id'])
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Semantics(
                            label: '当前课表',
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: '删除${table['name']}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _locked ? null : () => _delete(table),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _TableNameField extends StatefulWidget {
  final String name;
  final bool enabled, current;
  final Future<bool> Function(String) onSave;
  final VoidCallback onSelect;
  const _TableNameField({
    super.key,
    required this.name,
    required this.enabled,
    required this.current,
    required this.onSave,
    required this.onSelect,
  });

  @override
  State<_TableNameField> createState() => _TableNameFieldState();
}

class _TableNameFieldState extends State<_TableNameField> {
  late final _controller = TextEditingController(text: widget.name);
  String? _error;
  bool get _changed => _controller.text.trim() != widget.name;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!widget.enabled || !_changed) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '课表名称不能为空');
      return;
    }
    FocusScope.of(context).unfocus();
    if (await widget.onSave(name) && mounted) {
      setState(() => _controller.text = name);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    enabled: widget.enabled,
    textInputAction: TextInputAction.done,
    onTap: widget.onSelect,
    onSubmitted: (_) => _save(),
    onChanged: (_) => setState(() => _error = null),
    decoration: InputDecoration(
      labelText: widget.current ? '课表名称 · 当前课表' : '课表名称',
      errorText: _error,
      suffixIcon: _changed
          ? TextButton(
              onPressed: widget.enabled ? _save : null,
              child: const Text('保存'),
            )
          : null,
    ),
  );
}
