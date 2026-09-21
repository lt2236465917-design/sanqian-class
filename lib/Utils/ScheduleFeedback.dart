import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Models/ScheduleImportDraft.dart';

/// UI messages only. Import decisions and native error contracts stay unchanged.
class ScheduleFeedback {
  static String message(Object error, {required String fallback}) {
    if (error is ScheduleImportValidationException) {
      return '课程信息不完整或有重复，请检查课程名称、周次和起止时间后重试。';
    }
    final detail = switch (error) {
      StateError e => e.message,
      FormatException e => e.message,
      PlatformException e => e.message ?? e.code,
      _ => '',
    };
    final known = <String, String>{
      'import_review_stale': '课表在核对期间发生了变化，请重新查看变化后保存。',
      'import_source_account_or_term_mismatch':
          '所选课表的来源、账号或学期不同，请检查学期或重新选择保存位置。',
      'ambiguous_import_source': '找到多个同来源课表，请在“保存到”中明确选择一个。',
      'merge_table_missing': '所选课表已不存在，请重新选择保存位置。',
      'semester_start_required': '请选择学期第一周的周一后重试。',
      'invalid_class_time_list': '上课时间有误，请检查开始与结束时间后重试。',
      'ambiguous_duplicate_course': '存在无法区分的重复课程，请检查课程编码和安排。',
      'legacy_binding_duplicate_target': '多个安排关联了同一门已有课程，请重新选择关联。',
      'legacy_binding_invalid_target': '关联课程已变化，请重新查看变化并选择关联。',
      'legacy_binding_already_owned': '这门课程已关联其他来源，请重新选择关联。',
      'legacy_binding_requires_review_confirmation': '请重新核对课程关联后确认保存。',
      'import_changes_require_confirmation': '请先查看导入变化，再确认保存。',
    };
    if (known.containsKey(detail)) return known[detail]!;
    if (detail.contains('-34018')) {
      return '当前 App 安装无法访问本机安全存储，请更新或重新安装正确签名的 App 后重试。';
    }
    if (detail.contains('安全凭据存储')) {
      return '暂时无法访问本机安全存储，请解锁设备后重试。';
    }
    // Native recognizer errors already have user-facing Chinese descriptions.
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(detail)) return detail;
    return fallback;
  }

  static void success(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    // Replace the previous message, so its queued timer cannot hide new feedback.
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
    haptic();
  }

  static void haptic() =>
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
}
