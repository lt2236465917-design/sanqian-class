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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
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
                ),
                // One fixed capsule per tab slot. Android and iOS before 26
                // slide that box; a morphing lens reads as two cards overlapping.
                // Keep it outside BackdropFilter so those frames are not dropped.
                // The bar clip does not cover this layer, so the raised shadow
                // can sit on the glass instead of being cut into an inset.
                RepaintBoundary(
                  child: SizedBox(
                    key: const ValueKey('floating-schedule-bar'),
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final slot = constraints.maxWidth / _items.length;
                          return Stack(
                            clipBehavior: Clip.none,
                            fit: StackFit.expand,
                            children: [
                              AnimatedPositioned(
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                left: slot * selectedIndex,
                                width: slot,
                                top: 0,
                                bottom: 0,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    3,
                                    2,
                                    3,
                                    4,
                                  ),
                                  child: DecoratedBox(
                                    key: const ValueKey(
                                      'floating-tab-indicator',
                                    ),
                                    decoration: _raisedGlass(
                                      dark: dark,
                                      highContrast: highContrast,
                                      tint: colors.primary,
                                    ),
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(32),
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xE6FFFFFF),
                                            Color(0x55FFFFFF),
                                            Color(0x00FFFFFF),
                                          ],
                                          stops: [0, .14, .32],
                                        ),
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
                                        key: ValueKey(
                                          'tab-${_items[index].key}',
                                        ),
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 5,
                                                  ),
                                              shape: const StadiumBorder(),
                                              foregroundColor:
                                                  index == selectedIndex
                                                  ? colors.primary
                                                  : colors.onSurface,
                                              overlayColor: Colors.transparent,
                                              // The moving capsule is the only
                                              // selection shape. A splash paints
                                              // a second card on top of it.
                                              splashFactory:
                                                  NoSplash.splashFactory,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  _items[index].icon,
                                                  size: 23,
                                                ),
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
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A glass chip lit from above. The bright crown and the shadow underneath
  /// make it sit on the bar; a darker fill would read as a pressed-in well.
  BoxDecoration _raisedGlass({
    required bool dark,
    required bool highContrast,
    required Color tint,
  }) {
    final radius = BorderRadius.circular(32);
    final lip = Colors.white.withValues(alpha: dark ? .62 : 1);
    final shade = const Color(0xFF3C2A48).withValues(alpha: dark ? .55 : .22);
    if (highContrast) {
      return BoxDecoration(
        borderRadius: radius,
        color: dark ? const Color(0xFF3A3342) : Colors.white,
        border: Border.all(color: tint, width: 1.4),
        boxShadow: [
          BoxShadow(color: shade, blurRadius: 8, offset: const Offset(0, 4)),
        ],
      );
    }
    // Keep the body light. A darker bottom reads as a pressed-in well.
    // The shadow sits on the bar, under the chip.
    return BoxDecoration(
      borderRadius: radius,
      // Opaque enough that the drop shadow stays under the chip.
      // A translucent body lets that shadow show through and look inset.
      color: dark ? const Color(0xFF7C738C) : const Color(0xF7FFFFFF),
      border: Border.all(color: lip, width: 1.1),
      boxShadow: [
        BoxShadow(color: shade, blurRadius: 10, offset: const Offset(0, 4)),
        BoxShadow(
          color: tint.withValues(alpha: dark ? .18 : .08),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }
}
