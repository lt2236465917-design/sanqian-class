import 'package:flutter/material.dart';
import '../../../Components/ScheduleWheel.dart';
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
  static const _modes = [
    (Constant.FULL_WEEKS, '每周'),
    (Constant.SINGLE_WEEKS, '单周'),
    (Constant.DOUBLE_WEEKS, '双周'),
  ];
  late final Map _node = Map.from(widget.node);

  @override
  void initState() {
    super.initState();
    final type = _node['weekType'];
    if (!_modes.any((mode) => mode.$1 == type)) {
      _node['weekType'] = Constant.FULL_WEEKS;
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = CourseWeekSelection.weeks(_node).isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final dialogWidth = (MediaQuery.sizeOf(context).width - 80).clamp(
      220.0,
      340.0,
    );
    return AlertDialog(
      title: const Text('选择上课周'),
      scrollable: true,
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(child: Text('开始周')),
                SizedBox(width: 8),
                Expanded(child: Text('结束周')),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: ScheduleWheel(
                    items: [
                      for (var i = 0; i < Config.MAX_WEEKS; i++) '第 ${i + 1} 周',
                    ],
                    initialItem: _node['startWeek'] as int,
                    onChanged: (value) => setState(() {
                      _node['startWeek'] = value;
                      if (_node['endWeek'] < value) _node['endWeek'] = value;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ScheduleWheel(
                    key: ValueKey('end-week-${_node['startWeek']}'),
                    items: [
                      for (
                        var i = _node['startWeek'] as int;
                        i < Config.MAX_WEEKS;
                        i++
                      )
                        '第 ${i + 1} 周',
                    ],
                    initialItem:
                        (_node['endWeek'] as int) - (_node['startWeek'] as int),
                    onChanged: (value) => setState(
                      () => _node['endWeek'] =
                          (_node['startWeek'] as int) + value,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < _modes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      key: ValueKey('week-mode-${_modes[i].$1}'),
                      showCheckmark: false,
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _modes[i].$2,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      selected: _node['weekType'] == _modes[i].$1,
                      onSelected: (_) =>
                          setState(() => _node['weekType'] = _modes[i].$1),
                      pressElevation: 0,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      labelPadding: EdgeInsets.zero,
                      backgroundColor: scheme.surface,
                      selectedColor: Color.alphaBlend(
                        scheme.primary.withValues(alpha: .22),
                        scheme.primaryContainer,
                      ),
                      side: BorderSide(
                        color: _node['weekType'] == _modes[i].$1
                            ? scheme.primary
                            : scheme.outlineVariant.withValues(alpha: .7),
                      ),
                      labelStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _node['weekType'] == _modes[i].$1
                            ? scheme.primary
                            : scheme.onSurface,
                      ),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  CourseWeekSelection.summary(_node),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: valid ? null : scheme.error),
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
