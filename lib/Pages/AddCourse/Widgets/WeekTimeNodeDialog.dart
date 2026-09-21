import 'package:flutter/cupertino.dart';

import '../../../generated/l10n.dart';
import '../../../Resources/Constant.dart';
import '../../../Components/Dialog.dart';

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
  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _startController;
  late final FixedExtentScrollController _endController;
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
    _dayController = FixedExtentScrollController(
      initialItem: _node['weekTime'],
    );
    _startController = FixedExtentScrollController(
      initialItem: _node['startTime'],
    );
    _endController = FixedExtentScrollController(initialItem: _node['endTime']);
  }

  @override
  void dispose() {
    _dayController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> periodLabels() => List.generate(
      _periods.length,
      (index) => Center(
        child: Text(
          _periods[index]['label'] as String? ??
              S.of(context).class_single('${index + 1}'),
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
    return MDialog(
      S.of(context).choose_class_time_dialog_title,
      SizedBox(
        height: 128,
        child: Row(
          children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: _dayController,
                itemExtent: 36,
                onSelectedItemChanged: (index) => _node['weekTime'] = index,
                children: [
                  for (final day in Constant.WEEK_WITHOUT_BIAS)
                    Center(
                      child: Text(day, style: const TextStyle(fontSize: 15)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: _startController,
                itemExtent: 36,
                onSelectedItemChanged: (index) {
                  _node['startTime'] = index;
                  if (_node['endTime'] < index) {
                    _node['endTime'] = index;
                    _endController.jumpToItem(index);
                  }
                },
                children: periodLabels(),
              ),
            ),
            const Text('至'),
            Expanded(
              child: CupertinoPicker(
                scrollController: _endController,
                itemExtent: 36,
                onSelectedItemChanged: (index) {
                  _node['endTime'] = index;
                  if (_node['startTime'] > index) {
                    _node['startTime'] = index;
                    _startController.jumpToItem(index);
                  }
                },
                children: periodLabels(),
              ),
            ),
          ],
        ),
      ),
      widgetOK: Text(S.of(context).ok),
      widgetOKAction: () => Navigator.of(context).pop(_node),
    );
  }
}
