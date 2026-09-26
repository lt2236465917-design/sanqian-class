import 'package:flutter/material.dart';
import '../../../Components/ScheduleWheel.dart';
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
  late int _weekday;
  late int _startHour;
  late int _startMinute;
  late int _endHour;
  late int _endMinute;
  List<Map> get _periods =>
      widget.periods.isEmpty ? Constant.CLASS_TIME_LIST : widget.periods;

  @override
  void initState() {
    super.initState();
    _node = Map.from(widget.node);
    _weekday = ((_node['weekTime'] as int?) ?? 0).clamp(0, 6);
    final startIndex = ((_node['startTime'] as int?) ?? 0).clamp(
      0,
      _periods.length - 1,
    );
    final endIndex = ((_node['endTime'] as int?) ?? startIndex).clamp(
      startIndex,
      _periods.length - 1,
    );
    final start = _clock(_periods[startIndex]['start'], fallbackHour: 8);
    final end = _clock(_periods[endIndex]['end'], fallbackHour: 9);
    _startHour = start.$1;
    _startMinute = start.$2;
    _endHour = end.$1;
    _endMinute = end.$2;
  }

  (int, int) _clock(Object? value, {required int fallbackHour}) {
    final text = value?.toString() ?? '';
    final parts = text.split(':');
    if (parts.length != 2) return (fallbackHour, 0);
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return (fallbackHour, 0);
    return (hour.clamp(0, 23), minute.clamp(0, 59));
  }

  String _hhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  int get _startTotal => _startHour * 60 + _startMinute;
  int get _endTotal => _endHour * 60 + _endMinute;
  bool get _ordered => _endTotal > _startTotal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.sizeOf(context).width - 80).clamp(220.0, 340.0);
    return AlertDialog(
      title: const Text('选择上课时间'),
      scrollable: true,
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('星期'),
            ScheduleWheel(
              items: [
                for (var i = 0; i < 7; i++) Constant.WEEK_WITHOUT_BIAS[i],
              ],
              initialItem: _weekday,
              onChanged: (value) => setState(() => _weekday = value),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(child: Text('开始 · 时')),
                Expanded(child: Text('开始 · 分')),
                Expanded(child: Text('结束 · 时')),
                Expanded(child: Text('结束 · 分')),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: ScheduleWheel(
                    items: [for (var i = 0; i < 24; i++) i.toString().padLeft(2, '0')],
                    initialItem: _startHour,
                    onChanged: (value) => setState(() => _startHour = value),
                  ),
                ),
                Expanded(
                  child: ScheduleWheel(
                    items: [for (var i = 0; i < 60; i++) i.toString().padLeft(2, '0')],
                    initialItem: _startMinute,
                    onChanged: (value) => setState(() => _startMinute = value),
                  ),
                ),
                Expanded(
                  child: ScheduleWheel(
                    items: [for (var i = 0; i < 24; i++) i.toString().padLeft(2, '0')],
                    initialItem: _endHour,
                    onChanged: (value) => setState(() => _endHour = value),
                  ),
                ),
                Expanded(
                  child: ScheduleWheel(
                    items: [for (var i = 0; i < 60; i++) i.toString().padLeft(2, '0')],
                    initialItem: _endMinute,
                    onChanged: (value) => setState(() => _endMinute = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Text(
                _ordered
                    ? '${Constant.WEEK_WITHOUT_BIAS[_weekday]} ${_hhmm(_startHour, _startMinute)}–${_hhmm(_endHour, _endMinute)}'
                    : '结束时间需要晚于开始时间。',
                style: TextStyle(color: _ordered ? null : scheme.error),
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
          onPressed: _ordered
              ? () {
                  final span = ClassTimeUtil.periodSpan(
                    _periods,
                    _startTotal,
                    _endTotal,
                  );
                  Navigator.pop(context, {
                    ..._node,
                    'weekTime': _weekday,
                    'startTime': span?.start ?? _node['startTime'] ?? 0,
                    'endTime': span?.end ?? _node['endTime'] ?? 0,
                    'startClock': _hhmm(_startHour, _startMinute),
                    'endClock': _hhmm(_endHour, _endMinute),
                  });
                }
              : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}
