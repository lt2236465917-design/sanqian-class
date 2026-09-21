import 'package:flutter/material.dart';

import '../../../Utils/ScheduleDerivedDataService.dart';

/// Reads only whether a key is stored, never the key or remote account state.
class AIKeyStatus extends StatefulWidget {
  final int revision;
  const AIKeyStatus({super.key, required this.revision});

  @override
  State<AIKeyStatus> createState() => _AIKeyStatusState();
}

class _AIKeyStatusState extends State<AIKeyStatus> {
  bool? _hasKey;
  bool _loading = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AIKeyStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final saved = await ScheduleDerivedDataService.channel.invokeMethod<bool>(
        'hasAPIKey',
      );
      if (mounted && request == _request) {
        setState(() => _hasKey = saved ?? false);
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            _loading
                ? '正在检查 DeepSeek 配置…'
                : _failed
                ? '暂时无法读取 Key 配置，可重试或检查下方设置。'
                : _hasKey == true
                ? '已保存 DeepSeek Key · 识别时需联网验证'
                : '尚未配置 DeepSeek Key，请先打开下方设置。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_failed) TextButton(onPressed: _load, child: const Text('重新检查配置')),
      ],
    ),
  );
}
