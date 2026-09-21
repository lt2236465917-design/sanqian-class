import 'package:flutter/material.dart';
import '../../../Resources/Constant.dart';
import '../../../Utils/ClassTimeUtil.dart';

class WeekTimeNodeDialog extends StatefulWidget {
  final Map node;
  final List<Map> periods;
  static const Map map = {'weekTime': 0, 'startTime': 0, 'endTime': 0};
  const WeekTimeNodeDialog({
    this.node = map,
    this.periods = Constant.CLASS_TIME_LIST,
    super.key,
  });
  @override
  State<WeekTimeNodeDialog> createState() => _WeekTimeNodeDialogState();
}

class _WeekTimeNodeDialogState extends State<WeekTimeNodeDialog> {
  late final Map _node;
  List<Map> get _periods =>
      widget.periods.isEmpty ? Constant.CLASS_TIME_LIST : widget.periods;
  @override
  void initState() {
    super.initState();
    _node = Map.from(widget.node);
    _node['weekTime'] = ((_node['weekTime'] as int?) ?? 0).clamp(0, 6);
    _node['startTime'] = ((_node['startTime'] as int?) ?? 0).clamp(
      0,
      _periods.length - 1,
    );
    _node['endTime'] = ((_node['endTime'] as int?) ?? 0).clamp(
      _node['startTime'],
      _periods.length - 1,
    );
  }

  String _label(int index, String edge) =>
      ClassTimeUtil.hasClockTimes([_periods[index]])
      ? _periods[index][edge] as String
      : '${_periods[index]['label'] ?? '第 ${index + 1} 节'}${edge == 'start' ? '开始' : '结束'}';

  @override
  Widget build(BuildContext context) {
    final start = _node['startTime'] as int;
    final end = _node['endTime'] as int;
    final summary =
        ClassTimeUtil.clockRange(_periods, start + 1, end - start) ??
        ClassTimeUtil.rangeLabel(_periods, start + 1, end - start) ??
        '第 ${start + 1}–${end + 1} 节';
    return AlertDialog(
      title: const Text('选择上课时间'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _node['weekTime'],
              decoration: const InputDecoration(labelText: '星期'),
              isExpanded: true,
              items: [
                for (var i = 0; i < 7; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(Constant.WEEK_WITHOUT_BIAS[i]),
                  ),
              ],
              onChanged: (value) => setState(() => _node['weekTime'] = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: start,
              decoration: const InputDecoration(labelText: '开始时间'),
              isExpanded: true,
              items: [
                for (var i = 0; i < _periods.length; i++)
                  DropdownMenuItem(value: i, child: Text(_label(i, 'start'))),
              ],
              onChanged: (value) => setState(() {
                _node['startTime'] = value!;
                if (_node['endTime'] < value) _node['endTime'] = value;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey('end-time-$start-$end'),
              initialValue: end,
              decoration: const InputDecoration(labelText: '结束时间'),
              isExpanded: true,
              items: [
                for (var i = start; i < _periods.length; i++)
                  DropdownMenuItem(value: i, child: Text(_label(i, 'end'))),
              ],
              onChanged: (value) => setState(() => _node['endTime'] = value!),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                '${Constant.WEEK_WITHOUT_BIAS[_node['weekTime']]} $summary',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _node),
          child: const Text('确认'),
        ),
      ],
    );
  }
}
