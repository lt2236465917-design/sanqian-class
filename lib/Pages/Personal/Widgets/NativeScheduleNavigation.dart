import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// iOS owns the glass material, touch tracking, magnification and settling.
/// Keeping the whole tab bar native also lets its lens refract its own icons.
class NativeScheduleNavigation extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const NativeScheduleNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<NativeScheduleNavigation> createState() =>
      _NativeScheduleNavigationState();
}

class _NativeScheduleNavigationState extends State<NativeScheduleNavigation> {
  MethodChannel? _channel;

  Map<String, Object> get _configuration => {
    'selectedIndex': widget.selectedIndex,
    'dark': Theme.of(context).brightness == Brightness.dark,
    'tint': Theme.of(context).colorScheme.primary.toARGB32(),
  };

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('chaoxi/schedule_navigation/$id')
      ..setMethodCallHandler((call) async {
        if (!mounted || call.method != 'select') return;
        final index = call.arguments;
        if (index is int && index >= 0 && index < 3) {
          widget.onSelected(index);
        }
      });
    _update();
  }

  Future<void> _update() async {
    try {
      await _channel?.invokeMethod<void>('update', _configuration);
    } on PlatformException catch (error) {
      debugPrint('Schedule navigation update failed: ${error.code}');
    }
  }

  @override
  void didUpdateWidget(NativeScheduleNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Include the home-indicator area so UIKit can apply its own safe-area
    // layout; the extra space above leaves room for the expanding glass lens.
    return SizedBox(
      key: const ValueKey('native-schedule-bar'),
      height: 84 + MediaQuery.viewPaddingOf(context).bottom,
      child: UiKitView(
        viewType: 'chaoxi/schedule_tab_bar',
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
        gestureRecognizers: const {
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
    );
  }
}
