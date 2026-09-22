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
    body: SafeArea(
      child: ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
          '''创建 DeepSeek API Key 的完整流程

第 1 步：打开开放平台，注册 / 登录

在电脑浏览器打开：

platform.deepseek.com

用手机号或邮箱注册账号，然后登录。

第 2 步：完成实名认证

登录后，按平台提示完成实名认证。

只有认证通过后，才能进行充值和创建 API Key。

第 3 步：账户充值

进入充值页面，按提示选择支付宝或微信等方式充值。

DeepSeek API 是预付费模式：先充值，后使用。
如果余额不足，调用 API 时会报 402 错误。

第 4 步：创建 API Key

充值完成后，进入平台的：

API Keys 页面

点击创建 API Key，然后复制保存。

注意：API Key 通常只完整显示一次，一定要马上复制到安全的地方，比如记事本或密码管理器。

第 5 步：在代码或工具里使用

把你的 API Key 填到上方，就可以调用 DeepSeek 了。

---

安全提醒：API Key 千万不要泄露

· 不要发到微信群、QQ 群、朋友圈。
· 不要上传到 GitHub、网盘或公开文档。
· 不要截图给别人看。
· 一旦泄露，别人可能用你的余额调用 API。''',
          style: TextStyle(height: 1.6),
        ),
      ],
      ),
    ),
  );
}
