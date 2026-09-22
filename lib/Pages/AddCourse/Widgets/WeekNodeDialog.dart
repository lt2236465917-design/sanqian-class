import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../Resources/Constant.dart';
import '../../../Resources/Config.dart';
import '../../../Utils/CourseWeekSelection.dart';

class WeekNodeDialog extends StatefulWidget {
  final Map node;
  static const Map map = {
    'startWeek': 0,
    'endWeek': Config.MAX_WEEKS - 1,
    'weekType': Constant.FULL_WEEKS,
  };
  const WeekNodeDialog({this.node = map, super.key});

  @override
  State<WeekNodeDialog> createState() => _WeekNodeDialogState();
}

class _WeekNodeDialogState extends State<WeekNodeDialog> {
  late final Map _node;
  late final FixedExtentScrollController _startController;
  late final FixedExtentScrollController _endController;

  int _clampWeek(int value) => value.clamp(0, Config.MAX_WEEKS - 1).toInt();

  @override
  void initState() {
    super.initState();
    _node = Map.from(widget.node);
    _node['definedWeeks'] = [
      ...((_node['definedWeeks'] as List?) ?? CourseWeekSelection.weeks(_node)),
    ];
    _node['startWeek'] = _clampWeek(_node['startWeek'] as int);
    _node['endWeek'] = (_node['endWeek'] as int)
        .clamp(_node['startWeek'] as int, Config.MAX_WEEKS - 1)
        .toInt();
    _startController = FixedExtentScrollController(
      initialItem: _clampWeek(_node['startWeek'] as int),
    );
    _endController = FixedExtentScrollController(
      initialItem: (_node['endWeek'] as int) - (_node['startWeek'] as int),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  List<int> get _definedWeeks =>
      ((_node['definedWeeks'] as List?) ?? []).whereType<int>().toList()
        ..sort();

  void _setType(int type) {
    setState(() {
      _node['weekType'] = type;
      if (type == Constant.DEFINED_WEEKS && _definedWeeks.isEmpty) {
        _node['definedWeeks'] = CourseWeekSelection.weeks({
          ..._node,
          'weekType': Constant.FULL_WEEKS,
        });
      }
    });
  }

  Widget _weekPicker({
    required String label,
    required List<int> values,
    required FixedExtentScrollController controller,
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
            onSelectedItemChanged: (index) => onChanged(values[index]),
            children: [
              for (final week in values) Center(child: Text('第 ${week + 1} 周')),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final start = _clampWeek(_node['startWeek'] as int);
    final valid = CourseWeekSelection.weeks(_node).isNotEmpty;
    final allWeeks = [for (var i = 0; i < Config.MAX_WEEKS; i++) i];
    final endWeeks = [for (var i = start; i < Config.MAX_WEEKS; i++) i];

    return AlertDialog(
      title: const Text('选择上课周'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('上下滑动选择开始周和结束周', style: TextStyle(height: 1.4)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _weekPicker(
                    label: '开始周',
                    values: allWeeks,
                    controller: _startController,
                    onChanged: (value) => setState(() {
                      _node['startWeek'] = value;
                      if ((_node['endWeek'] as int) < value) {
                        _node['endWeek'] = value;
                      }
                      _endController.jumpToItem(
                        (_node['endWeek'] as int) - value,
                      );
                    }),
                  ),
                  const SizedBox(width: 12),
                  _weekPicker(
                    label: '结束周',
                    values: endWeeks,
                    controller: _endController,
                    onChanged: (value) =>
                        setState(() => _node['endWeek'] = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('上课规律', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var type = 0; type < Constant.WEEK_TYPES.length; type++)
                    ChoiceChip(
                      label: Text(
                        type == Constant.FULL_WEEKS
                            ? '每周'
                            : Constant.WEEK_TYPES[type],
                      ),
                      selected: _node['weekType'] == type,
                      onSelected: (_) => _setType(type),
                    ),
                ],
              ),
              if (_node['weekType'] == Constant.DEFINED_WEEKS) ...[
                const SizedBox(height: 12),
                const Text('自定义周次，可选择单独一周或不连续的多周。'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final week in allWeeks)
                      FilterChip(
                        label: Text('${week + 1}'),
                        selected: _definedWeeks.contains(week + 1),
                        onSelected: (selected) => setState(() {
                          final weeks = _definedWeeks;
                          if (selected) {
                            weeks.add(week + 1);
                          } else {
                            weeks.remove(week + 1);
                          }
                          _node['definedWeeks'] = weeks;
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  CourseWeekSelection.summary(_node),
                  style: TextStyle(
                    color: valid ? null : Theme.of(context).colorScheme.error,
                  ),
                ),
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
          onPressed: valid ? () => Navigator.pop(context, _node) : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}
