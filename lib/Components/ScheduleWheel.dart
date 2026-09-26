import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ScheduleWheel extends StatefulWidget {
  const ScheduleWheel({
    required this.items,
    required this.initialItem,
    required this.onChanged,
    super.key,
  });

  final List<String> items;
  final int initialItem;
  final ValueChanged<int> onChanged;

  @override
  State<ScheduleWheel> createState() => _ScheduleWheelState();
}

class _ScheduleWheelState extends State<ScheduleWheel> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    final index = widget.initialItem.clamp(0, widget.items.length - 1);
    _controller = FixedExtentScrollController(initialItem: index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 132,
      child: CupertinoPicker(
        scrollController: _controller,
        itemExtent: 32,
        onSelectedItemChanged: widget.onChanged,
        children: [
          for (final item in widget.items)
            Center(
              child: Text(item, style: TextStyle(fontSize: 16, color: color)),
            ),
        ],
      ),
    );
  }
}
