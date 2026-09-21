import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../Models/ScheduleImportDraft.dart';
import '../../Utils/ScheduleDerivedDataService.dart';
import '../../Utils/ScheduleFeedback.dart';
import '../Settings/DeepSeekSettingsView.dart';
import 'ImportReviewView.dart';
import 'Widgets/AIKeyStatus.dart';
import 'Widgets/RecognitionProgress.dart';

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
  int _keyRevision = 0;
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

  String _message(Object error) =>
      ScheduleFeedback.message(error, fallback: '操作未完成，请检查网络或图片后重试。已选图片保留。');

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DeepSeekSettingsView()),
    );
    if (mounted) setState(() => _keyRevision++);
  }

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
        await _openSettings();
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
          builder: (_) => ImportReviewView(
            courses: courses,
            source: 'photos',
            imagePaths: _images.map((image) => image.path).toList(),
          ),
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

  void _previewImage(int index) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('第 ${index + 1} 张课表图片')),
                    IconButton(
                      tooltip: '关闭原图',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.file(
                    File(_images[index].path),
                    fit: BoxFit.contain,
                    semanticLabel: '课表原图，可双指缩放',
                    errorBuilder: (_, error, stack) =>
                        const Center(child: Text('图片无法读取，请重新选择。')),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('双指缩放查看细节'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('多图课表导入')),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '选择同一学期的多张课表截图，由 AI 联合识别。保留星期、周次与时间表头；核对课程后再保存。',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('选择课表图片'),
          ),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '已选择 ${_images.length} 张',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '每次最多 20 张',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < _images.length; i++)
                    SizedBox(
                      width: 126,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Semantics(
                              button: true,
                              label: '查看第 ${i + 1} 张课表原图',
                              child: InkWell(
                                onTap: _busy ? null : () => _previewImage(i),
                                child: ExcludeSemantics(
                                  child: SizedBox(
                                    width: 126,
                                    height: 104,
                                    child: Image.file(
                                      File(_images[i].path),
                                      fit: BoxFit.cover,
                                      cacheWidth: 300,
                                      errorBuilder: (_, error, stack) =>
                                          const Center(
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _images.removeAt(i)),
                              icon: const Icon(Icons.close, size: 16),
                              label: Text('移除第 ${i + 1} 张'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          AIKeyStatus(revision: _keyRevision),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'AI 识别需要联网和 DeepSeek Key。确认发送后，所选图片会发送到 DeepSeek，可能消耗账户余额。',
            ),
          ),
          FilledButton(
            onPressed: _busy || _images.isEmpty ? null : _recognize,
            child: Text(_recognizing ? 'AI 正在识别…' : 'AI 识别课表'),
          ),
          TextButton(
            onPressed: _busy ? null : _openSettings,
            child: const Text('DeepSeek 设置'),
          ),
          if (_recognizing) ...[
            const RecognitionProgress(),
            TextButton(onPressed: _cancel, child: const Text('取消识别')),
          ],
          if (_error.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
