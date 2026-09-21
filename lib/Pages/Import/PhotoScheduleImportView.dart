import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../Models/ScheduleImportDraft.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../Settings/DeepSeekSettingsView.dart';
import 'ImportReviewView.dart';

class PhotoScheduleImportView extends StatefulWidget {
  const PhotoScheduleImportView({super.key});
  @override
  State<PhotoScheduleImportView> createState() =>
      _PhotoScheduleImportViewState();
}

class _PhotoScheduleImportViewState extends State<PhotoScheduleImportView> {
  List<XFile> _images = [];
  bool _busy = false, _recognizing = false;
  int _ticket = 0;
  String _error = '';

  @override
  void dispose() {
    _ticket++;
    if (_recognizing) {
      unawaited(
        ScheduleDerivedDataService.channel
            .invokeMethod<void>('cancelRecognition')
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  String _message(Object error) => error is PlatformException
      ? error.message ?? 'AI 识别失败，请重试'
      : error is FormatException
      ? error.message
      : '操作未完成，请重试';

  Future<void> _pick() async {
    try {
      final images = await ImagePicker().pickMultiImage();
      if (!mounted || images.isEmpty) return;
      if (images.length > 20) {
        setState(() => _error = '每次最多选择 20 张课表图片');
        return;
      }
      setState(() {
        _images = images;
        _error = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  Future<void> _recognize() async {
    if (_busy || _images.isEmpty) return;
    final ticket = ++_ticket;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final hasKey =
          await ScheduleDerivedDataService.channel.invokeMethod<bool>(
            'hasAPIKey',
          ) ??
          false;
      if (!mounted || ticket != _ticket) return;
      if (!hasKey) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const DeepSeekSettingsView()),
        );
        if (mounted && ticket == _ticket) {
          setState(() => _error = '配置 Key 后，点击“AI 识别课表”继续；已选图片保留');
        }
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('使用 DeepSeek 识别'),
          content: const Text(
            '所选课表图片将发送到 DeepSeek，可能消耗账户余额。请勿选择含密码或其他私密资料的图片。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('发送并识别'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || ticket != _ticket) {
        return;
      }
      setState(() => _recognizing = true);
      final result = await ScheduleDerivedDataService.channel
          .invokeMapMethod<String, dynamic>('recognizePhotos', {
            'paths': _images.map((e) => e.path).toList(),
            'ai': true,
          });
      if (!mounted || ticket != _ticket) return;
      setState(() => _recognizing = false);
      final courses = (result?['courses'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (courses.isEmpty) {
        throw const FormatException('AI 未识别到课程，请选择清晰且包含表头的完整课表');
      }
      for (final course in courses) {
        if (ScheduleImportCourseDraft.fromJson(course).validate().isNotEmpty) {
          throw const FormatException('AI 返回的课程字段有误，本次未保存课程');
        }
      }
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ImportReviewView(courses: courses, source: 'photos'),
        ),
      );
      if (saved == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted && ticket == _ticket) setState(() => _error = _message(e));
    } finally {
      if (mounted && ticket == _ticket) {
        setState(() {
          _busy = false;
          _recognizing = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    final ticket = ++_ticket;
    try {
      await ScheduleDerivedDataService.channel.invokeMethod<void>(
        'cancelRecognition',
      );
    } catch (_) {
      /* The ticket also rejects a late result. */
    }
    if (mounted && ticket == _ticket) {
      setState(() {
        _busy = false;
        _recognizing = false;
        _error = '已取消识别，已选图片保留';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('多图课表导入')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('选择同一学期的多张课表截图，由 AI 联合识别。保留星期、周次与时间表头；核对课程后再保存。'),
        TextButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('选择课表图片'),
        ),
        Text('已选择 ${_images.length} 张'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy || _images.isEmpty ? null : _recognize,
          child: Text(_recognizing ? 'AI 正在识别…' : 'AI 识别课表'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DeepSeekSettingsView(),
                  ),
                ),
          child: const Text('DeepSeek 设置'),
        ),
        if (_recognizing) ...[
          const LinearProgressIndicator(),
          TextButton(onPressed: _cancel, child: const Text('取消识别')),
        ],
        if (_error.isNotEmpty)
          Text(
            _error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
