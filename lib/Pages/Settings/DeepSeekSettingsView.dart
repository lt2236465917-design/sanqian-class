import '../../Components/ScheduleDesign.dart';
import '../../Components/ScheduleFeedbackNotice.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../../Utils/ScheduleFeedback.dart';
import '../../Utils/SecretMask.dart';

class DeepSeekSettingsView extends StatefulWidget {
  const DeepSeekSettingsView({super.key});
  @override
  State<DeepSeekSettingsView> createState() => _DeepSeekSettingsViewState();
}

class _DeepSeekSettingsViewState extends State<DeepSeekSettingsView> {
  static final _createKey = Uri.parse('https://platform.deepseek.com/api_keys');
  final _key = TextEditingController();
  final _keyFocus = FocusNode();
  bool? _saved;
  bool _busy = false, _loading = true, _invalidKey = false, _isError = false;
  bool _keyMasked = false;
  String? _visibleMask;
  String _message = '';
  String? _openError;
  VoidCallback? _retry;
  @override
  void initState() {
    super.initState();
    _keyFocus.addListener(_onKeyFocus);
    _status();
  }

  void _onKeyFocus() {
    if (_keyFocus.hasFocus) {
      if (_keyMasked) {
        _keyMasked = false;
        _key.clear();
        if (mounted) setState(() {});
      }
      return;
    }
    if (_key.text.trim().isEmpty && _saved == true && _visibleMask != null) {
      _showMask(_visibleMask!);
      if (mounted) setState(() {});
    }
  }

  void _showMask(String mask) {
    _keyMasked = true;
    _visibleMask = mask;
    _key.text = mask;
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
      String? preview;
      if (value) {
        try {
          preview = await ScheduleDerivedDataService.channel
              .invokeMethod<String>('apiKeyPreview');
        } catch (_) {
          preview = null;
        }
      }
      if (mounted) {
        setState(() => _saved = value);
        if (value) _showMask(preview ?? SecretMask.placeholder);
      }
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
    _keyFocus.removeListener(_onKeyFocus);
    _keyFocus.dispose();
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  Future<void> _action(bool remove) async {
    if (_busy || _loading) return;
    final typed = _key.text.trim();
    if (!remove && (_keyMasked || typed.isEmpty)) {
      if (_saved == true && (_keyMasked || typed.isEmpty)) {
        if (_visibleMask != null) _showMask(_visibleMask!);
        setState(() => _message = 'Key 已保存在本机');
        return;
      }
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
        remove ? null : {'key': typed},
      );
      if (mounted) {
        if (remove) {
          _keyMasked = false;
          _visibleMask = null;
          _key.clear();
        } else {
          _showMask(SecretMask.apiKey(typed));
        }
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

  Future<void> _openCreatePage() async {
    setState(() => _openError = null);
    try {
      final opened = await launchUrl(
        _createKey,
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    setState(() {
      _openError = '暂时无法打开 DeepSeek 开放平台，请稍后重试。';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI设置')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          const ScheduleIntro(
            icon: Icons.auto_awesome_outlined,
            eyebrow: '课表识别',
            title: '连接你的 DeepSeek',
            description: 'Key 仅保存于本机安全存储。只有确认发送后才会调用识别，费用由你的账户承担。',
          ),
          const SizedBox(height: 20),
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
            focusNode: _keyFocus,
            enabled: !_busy && !_loading,
            obscureText: !_keyMasked,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'DeepSeek API key',
              hintText: _saved == true ? '输入新 Key 可替换' : null,
              helperText: _keyMasked ? '已保存，只显示脱敏内容。点按后可输入新 Key。' : null,
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
          const ScheduleSection('怎么创建'),
          const ScheduleNotice(
            '1. 打开 DeepSeek 开放平台并登录\n'
            '2. 进入 API keys，新建一把 Key\n'
            '3. 创建后立即复制，页面通常只完整显示一次\n'
            '4. 回到本页，粘贴到上方并保存',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openCreatePage,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('打开 DeepSeek 开放平台'),
          ),
          if (_openError != null) ...[
            const SizedBox(height: 12),
            ScheduleInlineFeedback(
              message: _openError!,
              actionLabel: '重试',
              onAction: _busy ? null : _openCreatePage,
            ),
          ],
          const ScheduleSection('安全提醒'),
          const ScheduleNotice.numbered([
            'Key 只写入本机安全存储。保存之后，填写框只显示脱敏后的 Key，不显示原文。',
            '不要把 Key 告诉他人，也不要放进截图、聊天或邮件。',
            '只有你在导入页确认识别后，课表图片或网页课表原文才会发给 DeepSeek，费用从你的 DeepSeek 账户扣除。',
            '学校账号、密码和验证码不会随识别发送。',
            '删除 Key 后，下次识别前需要重新保存。',
          ]),
        ],
      ),
    ),
  );
}
