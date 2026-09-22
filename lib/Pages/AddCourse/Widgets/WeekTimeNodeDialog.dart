import 'package:flutter/cupertino.dart';
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
  late final FixedExtentScrollController _weekController;
  late final FixedExtentScrollController _startController;
  late final FixedExtentScrollController _endController;

  List<Map> get _periods =>
      widget.periods.isEmpty ? Constant.CLASS_TIME_LIST : widget.periods;

  @override
  void initState() {
    super.initState();
    _node = Map.from(widget.node);
    _node['weekTime'] = (((_node['weekTime'] as int?) ?? 0).clamp(
      0,
      6,
    )).toInt();
    _node['startTime'] = (((_node['startTime'] as int?) ?? 0).clamp(
      0,
      _periods.length - 1,
    )).toInt();
    _node['endTime'] = (((_node['endTime'] as int?) ?? 0).clamp(
      _node['startTime'],
      _periods.length - 1,
    )).toInt();
    _weekController = FixedExtentScrollController(
      initialItem: _node['weekTime'] as int,
    );
    _startController = FixedExtentScrollController(
      initialItem: _node['startTime'] as int,
    );
    _endController = FixedExtentScrollController(
      initialItem: (_node['endTime'] as int) - (_node['startTime'] as int),
    );
  }

  @override
  void dispose() {
    _weekController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  String _label(int index, String edge) =>
      ClassTimeUtil.hasClockTimes([_periods[index]])
      ? _periods[index][edge] as String
      : '${_periods[index]['label'] ?? '第 ${index + 1} 节'}${edge == 'start' ? '开始' : '结束'}';

  Widget _picker({
    required String label,
    required FixedExtentScrollController controller,
    required List<String> values,
    required ValueChanged<int> onChanged,
  }) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SizedBox(
          height: 150,
          child: CupertinoPicker(
            itemExtent: 40,
            scrollController: controller,
            onSelectedItemChanged: onChanged,
            children: [for (final value in values) Center(child: Text(value))],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final week = _node['weekTime'] as int;
    final start = _node['startTime'] as int;
    final end = _node['endTime'] as int;
    final endValues = [
      for (var i = start; i < _periods.length; i++) _label(i, 'end'),
    ];
    final summary =
        ClassTimeUtil.clockRange(_periods, start + 1, end - start) ??
        ClassTimeUtil.rangeLabel(_periods, start + 1, end - start) ??
        '第 ${start + 1}–${end + 1} 节';

    return AlertDialog(
      title: const Text('选择上课时间'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('上下滑动选择星期和节次', style: TextStyle(height: 1.4)),
              const SizedBox(height: 8),
              _picker(
                label: '星期',
                controller: _weekController,
                values: Constant.WEEK_WITHOUT_BIAS,
                onChanged: (value) => setState(() => _node['weekTime'] = value),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _picker(
                    label: '开始时间',
                    controller: _startController,
                    values: [
                      for (var i = 0; i < _periods.length; i++)
                        _label(i, 'start'),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _node['startTime'] = value;
                        if ((_node['endTime'] as int) < value) {
                          _node['endTime'] = value;
                        }
                        _endController.jumpToItem(
                          (_node['endTime'] as int) - value,
                        );
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  _picker(
                    label: '结束时间',
                    controller: _endController,
                    values: endValues,
                    onChanged: (value) =>
                        setState(() => _node['endTime'] = start + value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text('${Constant.WEEK_WITHOUT_BIAS[week]} $summary'),
              ),
            ],
          ),
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
