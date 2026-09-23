import '../../Components/ScheduleDesign.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../Settings/DeepSeekSettingsView.dart';
import 'ImportReviewView.dart';
import 'Widgets/AIKeyStatus.dart';

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
  int _keyRevision = 0;
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

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DeepSeekSettingsView()),
    );
    if (mounted) setState(() => _keyRevision++);
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
            expectedCourseNames: (result['courses'] as List? ?? [])
                .whereType<Map>()
                .map((course) => course['name'])
                .whereType<String>()
                .toList(),
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
    appBar: AppBar(title: const Text('学校账号导入课表')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          const ScheduleIntro(
            icon: Icons.school_outlined,
            eyebrow: '中国艺术研究院 · 研究生',
            title: '从学校带入课表',
            description: '使用学号或统一身份认证用户名。验证码在学校网页填写，读取后先核对，再保存。',
          ),
          const ImportJourney(step: 0),
          const ScheduleSection('学校账号', subtitle: '可以留空，在学校网页中自行登录。'),
          if (_localId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ScheduleNotice(
                '本机已记住账号 $_savedAccount。密码会自动填入学校网页，验证码和登录仍由你确认。',
              ),
            ),
          TextField(
            controller: _account,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '学号或学校登录名（可留空）'),
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
              labelText: _localId == null ? '学校网页密码（可留空）' : '新密码（留空则不改本机保存）',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _open,
            child: Text(_busy ? '正在打开学校网页…' : '打开学校网页'),
          ),
          TextButton(
            onPressed: _busy || _localId == null ? null : _clear,
            child: const Text('清除已保存账号'),
          ),
          const SizedBox(height: 8),
          if (_message.isNotEmpty) ScheduleNotice(_message),
          const ScheduleSection('打开网页后'),
          const ScheduleNotice(
            '1. 填写验证码，点击学校网页里的“登录”\n2. 进入“研究生综合管理 → 我的课表”\n3. 看到课表后，点右上角“读取并识别”',
          ),
          const ScheduleSection('识别课表'),
          AIKeyStatus(revision: _keyRevision),
          const ScheduleNotice(
            '读取到课表后，用本机保存的 API Key 让 DeepSeek 识别课程、周次、时间和教室。只有你确认发送才会联网，并可能消耗账户余额。学校账号、密码和验证码不会一起发送。',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _openSettings,
              child: const Text('DeepSeek 设置'),
            ),
          ),
        ],
      ),
    ),
  );
}
