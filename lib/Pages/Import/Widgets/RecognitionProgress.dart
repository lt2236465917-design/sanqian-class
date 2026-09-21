import 'package:flutter/material.dart';

/// A scanning cue for the actual recognition request, with no invented progress.
class RecognitionProgress extends StatefulWidget {
  const RecognitionProgress({super.key});

  @override
  State<RecognitionProgress> createState() => _RecognitionProgressState();
}

class _RecognitionProgressState extends State<RecognitionProgress>
    with SingleTickerProviderStateMixin {
  late final _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reduceMotion) {
      _scan.stop();
    } else if (!_scan.isAnimating) {
      _scan.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'AI 正在识别课表，完成后可核对；也可以取消识别。',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 正在识别课表，完成后可核对'),
              if (!_reduceMotion) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 3,
                  child: AnimatedBuilder(
                    animation: _scan,
                    builder: (context, child) => Align(
                      alignment: Alignment(_scan.value * 2 - 1, 0),
                      child: FractionallySizedBox(
                        widthFactor: .28,
                        child: child,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
