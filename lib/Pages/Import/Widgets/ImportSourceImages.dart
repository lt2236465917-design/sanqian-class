import 'dart:io';

import 'package:flutter/material.dart';

/// The same local-only viewer is used before recognition, during review and
/// while editing. Opening a route preserves the caller's fields and scroll.
Future<void> showImportSourceImages(
  BuildContext context, {
  required List<String> imagePaths,
  int initialIndex = 0,
}) async {
  if (imagePaths.isEmpty) return;
  FocusScope.of(context).unfocus();
  await showDialog<void>(
    context: context,
    builder: (_) => _ImportSourceImages(
      imagePaths: List.unmodifiable(imagePaths),
      initialIndex: initialIndex.clamp(0, imagePaths.length - 1),
    ),
  );
}

class ImportSourceImagesButton extends StatelessWidget {
  final List<String> imagePaths;
  final bool enabled;
  const ImportSourceImagesButton({
    super.key,
    required this.imagePaths,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => imagePaths.isEmpty
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: enabled
              ? () => showImportSourceImages(context, imagePaths: imagePaths)
              : null,
          icon: const Icon(Icons.image_outlined, size: 20),
          label: const Text('查看原图'),
        );
}

class _ImportSourceImages extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;
  const _ImportSourceImages({
    required this.imagePaths,
    required this.initialIndex,
  });

  @override
  State<_ImportSourceImages> createState() => _ImportSourceImagesState();
}

class _ImportSourceImagesState extends State<_ImportSourceImages> {
  final _transform = TransformationController();
  late int _index = widget.initialIndex;
  Size _viewport = Size.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _show(int index) {
    _transform.value = Matrix4.identity();
    setState(() => _index = index);
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 8.0);
    if (next == 1) {
      _transform.value = Matrix4.identity();
      return;
    }
    final center = _viewport.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(next / current, next / current, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '第 ${_index + 1} 张课表图片',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭原图',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                return InteractiveViewer(
                  key: ValueKey('import-source-image-$_index'),
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 8,
                  child: SizedBox.expand(
                    child: Image.file(
                      File(widget.imagePaths[_index]),
                      fit: BoxFit.contain,
                      semanticLabel: '第 ${_index + 1} 张课表原图，可双指缩放',
                      errorBuilder: (_, error, stack) =>
                          const Center(child: Text('原图暂时无法读取。')),
                    ),
                  ),
                );
              },
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            children: [
              IconButton(
                tooltip: '上一张原图',
                onPressed: _index > 0 ? () => _show(_index - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_index + 1} / ${widget.imagePaths.length}'),
              IconButton(
                tooltip: '下一张原图',
                onPressed: _index + 1 < widget.imagePaths.length
                    ? () => _show(_index + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: '缩小原图',
                onPressed: () => _zoom(0.5),
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: '放大原图',
                onPressed: () => _zoom(2),
                icon: const Icon(Icons.zoom_in),
              ),
              TextButton(
                onPressed: () => _transform.value = Matrix4.identity(),
                child: const Text('重置缩放'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('双指缩放，放大后拖动查看细节'),
          ),
        ],
      ),
    ),
  );
}
