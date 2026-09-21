import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import 'ImportReviewView.dart';

class SchoolAccountView extends StatefulWidget {
  const SchoolAccountView({super.key});
  @override
  State<SchoolAccountView> createState() => _SchoolAccountViewState();
}

class _SchoolAccountViewState extends State<SchoolAccountView> {
  final _account = TextEditingController(), _password = TextEditingController();
  String? _localId;
  String _savedAccount = '';
  bool _busy = false;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ScheduleDerivedDataService.channel
          .invokeMapMethod<String, dynamic>('schoolAccount');
      if (mounted && data != null) {
        setState(() {
          _account.text = data['account'] as String? ?? '';
          _localId = data['accountLocalId'] as String?;
          _savedAccount = _account.text;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _errorText(e));
    }
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _account.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      if (_localId != null &&
          _account.text.trim() != _savedAccount &&
          _password.text.isEmpty) {
        throw const FormatException('更换账号时请填写该账号的密码');
      }
      if (_password.text.isNotEmpty) {
        final saved = await ScheduleDerivedDataService.channel
            .invokeMapMethod<String, dynamic>('saveSchoolAccount', {
              'account': _account.text,
              'password': _password.text,
            });
        if (!mounted) return;
        if (saved?['accountLocalId'] is! String ||
            saved?['account'] is! String) {
          throw const FormatException('账号保存未完成，请重试');
        }
        _localId = saved!['accountLocalId'] as String;
        _savedAccount = saved['account'] as String;
        _account.text = _savedAccount;
        _password.clear();
      }
      if (!mounted) return;
      if (_localId == null) throw const FormatException('请先填写学校账号和密码，保存在本机');
      final result = await ScheduleDerivedDataService.channel
          .invokeMapMethod<String, dynamic>('openPortal');
      if (result == null || !mounted) return;
      final timetableText = result['timetableText'] as String?;
      if ((timetableText ?? '').trim().isEmpty) {
        final warnings = (result['warnings'] as List? ?? [])
            .whereType<String>()
            .join('；');
        throw FormatException(
          warnings.isEmpty
              ? '未读取到可供 AI 识别的课表原文，请进入“我的课表”后重试，或使用多图课表导入'
              : '$warnings 可改用多图课表导入。',
        );
      }
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ImportReviewView(
            courses: const [],
            source: 'school-portal',
            accountLocalId: _localId,
            timetableText: timetableText,
            warnings: (result['warnings'] as List? ?? [])
                .whereType<String>()
                .toList(),
          ),
        ),
      );
      if (saved == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _message = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    try {
      await ScheduleDerivedDataService.channel.invokeMethod(
        'deleteSchoolAccount',
      );
      if (mounted) {
        setState(() {
          _localId = null;
          _account.clear();
          _password.clear();
          _message = '已清除账号，已导入课表仍保留';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _errorText(e));
    }
  }

  String _errorText(Object error) {
    if (error is PlatformException) {
      if (error.message?.contains('-34018') == true) {
        return '当前安装版本缺少安全存储权限，账号未能保存。请更新应用后重试。';
      }
      return error.message ?? '暂时无法打开学校网页，请重试';
    }
    if (error is FormatException) return error.message;
    return '操作未完成，请重试';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('学校账号与导入')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '中国艺术研究院\n在学校网页完成登录、验证码，进入“研究生综合管理 → 我的课表”，再读取并用 AI 识别，核对后保存。',
        ),
        const SizedBox(height: 16),
        Text(
          _localId == null ? '未保存账号' : '已保存账号（不代表当前网页登录成功）',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _account,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: '学校账号'),
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: _localId == null ? '密码' : '新密码（留空使用已保存密码）',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _open,
          child: Text(_busy ? '正在打开学校网页…' : '登录并导入'),
        ),
        TextButton(
          onPressed: _busy || _localId == null ? null : _clear,
          child: const Text('清除已保存账号'),
        ),
        const SizedBox(height: 8),
        Text(_message, style: const TextStyle(height: 1.5)),
      ],
    ),
  );
}
