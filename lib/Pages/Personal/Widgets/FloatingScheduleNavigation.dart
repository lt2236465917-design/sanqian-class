import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'NativeScheduleNavigation.dart';

class FloatingScheduleNavigation extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const FloatingScheduleNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<FloatingScheduleNavigation> createState() =>
      _FloatingScheduleNavigationState();
}

class _FloatingScheduleNavigationState
    extends State<FloatingScheduleNavigation> {
  bool _nativeGlass = false;

  @override
  void initState() {
    super.initState();
    _checkNativeGlass();
  }

  Future<void> _checkNativeGlass() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final supported = await const MethodChannel(
        'chaoxi/schedule_navigation',
      ).invokeMethod<bool>('isSupported');
      if (mounted && supported == true) setState(() => _nativeGlass = true);
    } on MissingPluginException {
      // Older builds and non-iOS targets keep the accessible Flutter bar.
    } on PlatformException catch (error) {
      debugPrint('Native schedule navigation unavailable: ${error.code}');
    }
  }

  @override
  Widget build(BuildContext context) => _nativeGlass
      ? NativeScheduleNavigation(
          selectedIndex: widget.selectedIndex,
          onSelected: widget.onSelected,
        )
      : _FrostedScheduleNavigation(
          selectedIndex: widget.selectedIndex,
          onSelected: widget.onSelected,
        );
}

class _FrostedScheduleNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _FrostedScheduleNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  static const _items = [
    (key: 'today', label: '日课表', icon: Icons.wb_sunny_rounded),
    (key: 'week', label: '周课表', icon: Icons.apps_rounded),
    (key: 'month', label: '月课表', icon: Icons.calendar_month_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final duration =
        (MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context))
        ? Duration.zero
        : const Duration(milliseconds: 360);
    final height =
        64.0 + (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 32);
    final glass = dark ? const Color(0xFF29262E) : const Color(0xFFFFFCF6);
    final rim = Colors.white.withValues(alpha: dark ? .15 : .78);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .25 : .08),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: colors.primary.withValues(alpha: .04),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: highContrast ? 0 : 16,
                        sigmaY: highContrast ? 0 : 16,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: glass.withValues(
                            alpha: highContrast
                                ? .96
                                : dark
                                ? .76
                                : .72,
                          ),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: rim, width: .8),
                        ),
                      ),
                    ),
                  ),
                  // Keep the lens above the blur. Inside BackdropFilter, iOS
                  // drops the in-between frames and the pill jumps.
                  SizedBox(
                    key: const ValueKey('floating-schedule-bar'),
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // One moving lens keeps the transition continuous.
                          AnimatedAlign(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            alignment: Alignment(
                              -1 + selectedIndex.toDouble(),
                              0,
                            ),
                            child: FractionallySizedBox(
                              widthFactor: 1 / _items.length,
                              heightFactor: 1,
                              child: Container(
                                key: const ValueKey('floating-tab-indicator'),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: dark
                                        ? [
                                            Colors.white.withValues(alpha: .17),
                                            colors.primary.withValues(
                                              alpha: .12,
                                            ),
                                          ]
                                        : [
                                            const Color(
                                              0xFFECE7EE,
                                            ).withValues(alpha: .86),
                                            const Color(
                                              0xFFE3DEE7,
                                            ).withValues(alpha: .64),
                                          ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                      alpha: dark ? .22 : .8,
                                    ),
                                    width: .8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (
                                var index = 0;
                                index < _items.length;
                                index++
                              )
                                Expanded(
                                  child: Semantics(
                                    key: ValueKey('tab-${_items[index].key}'),
                                    container: true,
                                    button: true,
                                    selected: index == selectedIndex,
                                    inMutuallyExclusiveGroup: true,
                                    label: _items[index].label,
                                    onTap: () => onSelected(index),
                                    child: ExcludeSemantics(
                                      child: TextButton(
                                        onPressed: () => onSelected(index),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(44, 44),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 5,
                                          ),
                                          shape: const StadiumBorder(),
                                          foregroundColor:
                                              index == selectedIndex
                                              ? colors.primary
                                              : colors.onSurface,
                                          overlayColor: colors.primary
                                              .withValues(alpha: .08),
                                          // iOS otherwise uses a spreading ripple.
                                          // Android's press is InkSparkle.
                                          splashFactory:
                                              defaultTargetPlatform ==
                                                  TargetPlatform.iOS
                                              ? InkSparkle.splashFactory
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(_items[index].icon, size: 23),
                                            const SizedBox(height: 3),
                                            Text(
                                              _items[index].label,
                                              style: TextStyle(
                                                fontSize: 11,
                                                height: 1.1,
                                                fontWeight:
                                                    index == selectedIndex
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
