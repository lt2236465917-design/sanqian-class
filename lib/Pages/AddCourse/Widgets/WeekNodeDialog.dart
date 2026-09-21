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
  late final Map _node = Map.from(widget.node);

  @override
  Widget build(BuildContext context) {
    final valid = CourseWeekSelection.weeks(_node).isNotEmpty;
    return AlertDialog(
      title: const Text('选择上课周'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _node['startWeek'],
              decoration: const InputDecoration(labelText: '开始周'),
              isExpanded: true,
              items: [
                for (var i = 0; i < Config.MAX_WEEKS; i++)
                  DropdownMenuItem(value: i, child: Text('第 ${i + 1} 周')),
              ],
              onChanged: (value) => setState(() {
                _node['startWeek'] = value!;
                if (_node['endWeek'] < value) _node['endWeek'] = value;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey(
                'end-week-${_node['startWeek']}-${_node['endWeek']}',
              ),
              initialValue: _node['endWeek'],
              decoration: const InputDecoration(labelText: '结束周'),
              isExpanded: true,
              items: [
                for (
                  var i = _node['startWeek'] as int;
                  i < Config.MAX_WEEKS;
                  i++
                )
                  DropdownMenuItem(value: i, child: Text('第 ${i + 1} 周')),
              ],
              onChanged: (value) => setState(() => _node['endWeek'] = value!),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (var type = 0; type < Constant.WEEK_TYPES.length; type++)
                  ChoiceChip(
                    label: Text(
                      type == Constant.FULL_WEEKS
                          ? '每周'
                          : Constant.WEEK_TYPES[type],
                    ),
                    selected: _node['weekType'] == type,
                    onSelected: (_) => setState(() => _node['weekType'] = type),
                  ),
              ],
            ),
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
