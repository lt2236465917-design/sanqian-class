import 'package:flutter/material.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../../Utils/ScheduleFeedback.dart';

class DeepSeekSettingsView extends StatefulWidget {
  const DeepSeekSettingsView({super.key});
  @override
  State<DeepSeekSettingsView> createState() => _DeepSeekSettingsViewState();
}

class _DeepSeekSettingsViewState extends State<DeepSeekSettingsView> {
  final _key = TextEditingController();
  bool? _saved;
  bool _busy = false, _loading = true, _invalidKey = false, _isError = false;
  String _message = '';
  VoidCallback? _retry;
  @override
  void initState() {
    super.initState();
    _status();
  }

  Future<void> _status() async {
    setState(() {
      _loading = true;
      _message = '';
      _retry = null;
    });
    try {
      final value =
          await ScheduleDerivedDataService.channel.invokeMethod<bool>(
            'hasAPIKey',
          ) ??
          false;
      if (mounted) setState(() => _saved = value);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = ScheduleFeedback.message(
            e,
            fallback: '暂时无法读取 Key 状态，请重试。',
          );
          _retry = _status;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  Future<void> _action(bool remove) async {
    if (_busy || _loading) return;
    if (!remove && _key.text.trim().isEmpty) {
      setState(() => _invalidKey = true);
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
      _retry = null;
      _invalidKey = false;
    });
    try {
      await ScheduleDerivedDataService.channel.invokeMethod(
        remove ? 'deleteAPIKey' : 'saveAPIKey',
        remove ? null : {'key': _key.text.trim()},
      );
      if (mounted) {
        _key.clear();
        setState(() {
          _saved = !remove;
          _isError = false;
          _message = remove ? '已删除 Key' : 'Key 已保存到本机安全存储';
        });
        ScheduleFeedback.haptic();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = ScheduleFeedback.message(
            e,
            fallback: remove ? '删除未完成，请重试。' : '保存未完成，输入已保留，请重试。',
          );
          _retry = () => _action(remove);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DeepSeek 设置')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _loading
              ? '正在读取 Key 状态…'
              : _saved == null
              ? 'Key 状态暂不可用'
              : _saved!
              ? '已保存 Key · ••••••••'
              : '尚未保存 Key',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          enabled: !_busy && !_loading,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'DeepSeek API key',
            hintText: _saved == true ? '输入新 Key 可替换' : null,
            errorText: _invalidKey ? '请先填写 Key' : null,
          ),
          onChanged: (_) {
            if (_invalidKey) setState(() => _invalidKey = false);
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _loading ? null : () => _action(false),
          child: Text(_busy ? '正在更新 Key…' : '保存'),
        ),
        TextButton(
          onPressed: _busy || _loading || _saved != true
              ? null
              : () => _action(true),
          child: const Text('删除 Key'),
        ),
        const SizedBox(height: 8),
        if (_message.isNotEmpty)
          Semantics(
            liveRegion: true,
            child: Text(
              _message,
              style: TextStyle(
                height: 1.5,
                color: _isError ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
        if (_retry != null)
          TextButton(
            onPressed: _busy || _loading ? null : _retry,
            child: const Text('重试'),
          ),
        const SizedBox(height: 16),
        const Text(
          '多图课表与学校网页课表均使用 DeepSeek 识别。确认发送后，所选图片或课表文字会发送到 DeepSeek，并可能消耗账户余额。',
        ),
      ],
    ),
  );
}
