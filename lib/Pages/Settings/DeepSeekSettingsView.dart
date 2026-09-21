import 'package:flutter/material.dart';
import '../../Utils/ScheduleDerivedDataService.dart';

class DeepSeekSettingsView extends StatefulWidget {
  const DeepSeekSettingsView({super.key});
  @override
  State<DeepSeekSettingsView> createState() => _DeepSeekSettingsViewState();
}

class _DeepSeekSettingsViewState extends State<DeepSeekSettingsView> {
  final _key = TextEditingController();
  bool _saved = false, _busy = false;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _status();
  }

  Future<void> _status() async {
    try {
      final value =
          await ScheduleDerivedDataService.channel.invokeMethod<bool>(
            'hasAPIKey',
          ) ??
          false;
      if (mounted) setState(() => _saved = value);
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    }
  }

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  Future<void> _action(bool remove) async {
    setState(() => _busy = true);
    try {
      await ScheduleDerivedDataService.channel.invokeMethod(
        remove ? 'deleteAPIKey' : 'saveAPIKey',
        remove ? null : {'key': _key.text},
      );
      _key.clear();
      await _status();
      if (mounted) {
        setState(() => _message = remove ? '已删除 Key' : 'Key 已保存到本机安全存储');
      }
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
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
        Text(_saved ? '已保存 Key · ••••••••' : '尚未保存 Key'),
        TextField(
          controller: _key,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'DeepSeek API key',
            hintText: _saved ? '输入新 Key 可替换' : null,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _action(false),
          child: const Text('保存'),
        ),
        TextButton(
          onPressed: _busy || !_saved ? null : () => _action(true),
          child: const Text('删除 Key'),
        ),
        Text(_message),
        const SizedBox(height: 16),
        const Text(
          '多图课表与学校网页课表均使用 DeepSeek 识别。确认发送后，所选图片或课表文字会发送到 DeepSeek，并可能消耗账户余额。',
        ),
      ],
    ),
  );
}
