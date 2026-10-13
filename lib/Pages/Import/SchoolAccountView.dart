import 'dart:async';

import '../../Components/ScheduleDesign.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../../Utils/SecretMask.dart';
import '../Settings/DeepSeekSettingsView.dart';
import 'ImportReviewView.dart';
import 'Widgets/AIKeyStatus.dart';

class SchoolAccountView extends StatefulWidget {
  const SchoolAccountView({super.key});
  @override
  State<SchoolAccountView> createState() => _SchoolAccountViewState();
}

class _SchoolAccountViewState extends State<SchoolAccountView> {
  static const _autoSaveDelay = Duration(milliseconds: 700);
  final _account = TextEditingController(), _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _localId;
  String _savedAccount = '';
  bool _busy = false;
  bool _hydrating = false;
  bool _passwordMasked = false;
  int _keyRevision = 0;
  String _message = '';
  Timer? _autoSaveTimer;
  Future<void>? _saveInFlight;
  @override
  void initState() {
    super.initState();
    _account.addListener(_onCredentialEdited);
    _password.addListener(_onCredentialEdited);
    _passwordFocus.addListener(_onPasswordFocus);
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ScheduleDerivedDataService.channel
          .invokeMapMethod<String, dynamic>('schoolAccount');
      if (mounted && data != null) {
        _hydrating = true;
        _account.text = data['account'] as String? ?? '';
        _localId = data['accountLocalId'] as String?;
        _savedAccount = _account.text;
        if (_localId != null) _applyPasswordMask();
        _hydrating = false;
        setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _message = _errorText(e));
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _account.removeListener(_onCredentialEdited);
    _password.removeListener(_onCredentialEdited);
    _passwordFocus.removeListener(_onPasswordFocus);
    final account = _account.text.trim();
    final password = _password.text;
    if (_saveInFlight == null &&
        !_passwordMasked &&
        account.isNotEmpty &&
        password.isNotEmpty &&
        password != SecretMask.placeholder) {
      unawaited(
        ScheduleDerivedDataService.channel
            .invokeMapMethod('saveSchoolAccount', {
              'account': account,
              'password': password,
            })
            .then((_) {}, onError: (_, _) {}),
      );
    }
    _password.clear();
    _passwordFocus.dispose();
    _password.dispose();
    _account.dispose();
    super.dispose();
  }

  void _applyPasswordMask() {
    _passwordMasked = true;
    _password.text = SecretMask.placeholder;
  }

  void _onCredentialEdited() {
    if (_hydrating) return;
    if (_passwordMasked && _password.text != SecretMask.placeholder) {
      _passwordMasked = false;
    }
    _scheduleAutoSave();
  }

  void _onPasswordFocus() {
    if (_passwordFocus.hasFocus) {
      if (_passwordMasked) {
        _hydrating = true;
        _passwordMasked = false;
        _password.clear();
        _hydrating = false;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_password.text.isEmpty && _localId != null) {
      _hydrating = true;
      _applyPasswordMask();
      _hydrating = false;
      if (mounted) setState(() {});
      return;
    }
    _autoSaveTimer?.cancel();
    unawaited(
      _saveIfReady().catchError((Object error) {
        if (mounted) setState(() => _message = _errorText(error));
      }),
    );
  }

  void _scheduleAutoSave() {
    if (_busy) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      if (!mounted) return;
      unawaited(
        _saveIfReady().catchError((Object error) {
          if (mounted) setState(() => _message = _errorText(error));
        }),
      );
    });
  }

  bool get _passwordIsMask =>
      _passwordMasked || _password.text == SecretMask.placeholder;

  Future<void> _saveIfReady() {
    final current = _saveInFlight;
    if (current != null) return current;
    final run = _saveBody();
    _saveInFlight = run;
    return run.whenComplete(() {
      if (identical(_saveInFlight, run)) _saveInFlight = null;
    });
  }

  Future<void> _saveBody() async {
    final account = _account.text.trim();
    final password = _password.text;
    final masked = _passwordIsMask;
    if (account.isEmpty) return;
    if (masked && _localId != null && account == _savedAccount) return;
    if (masked && _localId == null) return;
    if (!masked && password.isEmpty) {
      if (_localId != null && account != _savedAccount) {
        throw const FormatException('更换账号时请填写该账号的密码');
      }
      return;
    }
    final saved = await ScheduleDerivedDataService.channel
        .invokeMapMethod<String, dynamic>('saveSchoolAccount', {
          'account': account,
          if (!masked) 'password': password,
          if (masked) 'keepPassword': true,
        });
    if (!mounted) return;
    if (saved?['accountLocalId'] is! String || saved?['account'] is! String) {
      throw const FormatException('账号保存未完成，请重试');
    }
    _hydrating = true;
    _localId = saved!['accountLocalId'] as String;
    _savedAccount = saved['account'] as String;
    _account.text = _savedAccount;
    _applyPasswordMask();
    _hydrating = false;
    if (_passwordFocus.hasFocus) _passwordFocus.unfocus();
    if (mounted) setState(() => _message = '');
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
    _autoSaveTimer?.cancel();
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await _saveIfReady();
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
    _autoSaveTimer?.cancel();
    try {
      await ScheduleDerivedDataService.channel.invokeMethod(
        'deleteSchoolAccount',
      );
      if (mounted) {
        _hydrating = true;
        _localId = null;
        _savedAccount = '';
        _passwordMasked = false;
        _account.clear();
        _password.clear();
        _hydrating = false;
        setState(() => _message = '已清除账号，已导入课表仍保留');
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
            eyebrow: '学校网页 · AI 识别',
            title: '从学校带入课表',
            description: '使用学号或统一身份认证用户名。验证码在学校网页填写，读取后先核对，再保存。',
          ),
          const SizedBox(height: 16),
          const ScheduleNotice('暂只支持中国艺术研究院，其他学校逐渐适配中。'),
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
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '学校网页密码（可留空）',
              helperText: _passwordMasked ? '已保存，只显示脱敏内容。点按后可输入新密码。' : null,
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
            '1. 填写验证码，点击学校网页里的“登录”\n2. 进入“研究生综合管理 → 我的课表”\n3. 看到课表后，点页面底部“读取并识别”',
          ),
          const ScheduleSection('识别课表'),
          AIKeyStatus(revision: _keyRevision),
          const ScheduleNotice(
            '读取到课表后，用本机保存的 API Key 让 DeepSeek 识别课程、周次、时间和教室。只有你确认发送才会联网，并可能消耗账户余额。学校账号、密码和验证码不会一起发送。',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
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
