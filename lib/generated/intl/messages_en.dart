// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(start, end) => "第 ${start}-${end} 节";

  static String m1(received, total) => "已接收 ${received}/${total}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "add_class": MessageLookupByLibrary.simpleMessage("添加课程"),
    "add_class_table_dialog_title": MessageLookupByLibrary.simpleMessage(
      "请输入课程表名称",
    ),
    "add_manually_title": MessageLookupByLibrary.simpleMessage("添加课程"),
    "cancel": MessageLookupByLibrary.simpleMessage("取消"),
    "class_duration": m0,
    "class_info": MessageLookupByLibrary.simpleMessage("备注"),
    "class_name": MessageLookupByLibrary.simpleMessage("课程名称"),
    "class_name_empty": MessageLookupByLibrary.simpleMessage("请输入课程名称"),
    "class_num_invalid_dialog_content": MessageLookupByLibrary.simpleMessage(
      "课程结束节数应大于起始节数",
    ),
    "class_num_invalid_dialog_title": MessageLookupByLibrary.simpleMessage(
      "课程节数不合法",
    ),
    "class_room": MessageLookupByLibrary.simpleMessage("上课地点"),
    "class_teacher": MessageLookupByLibrary.simpleMessage("上课老师"),
    "export_title": MessageLookupByLibrary.simpleMessage("导出课程表"),
    "import_from_qrcode_title": MessageLookupByLibrary.simpleMessage("导入课表"),
    "ok": MessageLookupByLibrary.simpleMessage("确认"),
    "qr_error_checksum_mismatch": MessageLookupByLibrary.simpleMessage(
      "二维码数据校验失败",
    ),
    "qr_error_payload_corrupted": MessageLookupByLibrary.simpleMessage(
      "二维码数据损坏",
    ),
    "qr_error_unsupported_protocol": MessageLookupByLibrary.simpleMessage(
      "二维码协议版本不支持",
    ),
    "qr_scan_from_clipboard_button": MessageLookupByLibrary.simpleMessage(
      "从剪贴板导入",
    ),
    "qr_scan_from_gallery_button": MessageLookupByLibrary.simpleMessage(
      "相册导入二维码",
    ),
    "qr_scan_parts_received_toast": m1,
    "qr_share_copy_button": MessageLookupByLibrary.simpleMessage("复制完整分享串"),
    "qr_share_copy_success_toast": MessageLookupByLibrary.simpleMessage(
      "已复制完整分享串",
    ),
    "qrcode_read_error_toast": MessageLookupByLibrary.simpleMessage(
      "读取课程表，可能是 bug",
    ),
    "qrcode_url_error_toast": MessageLookupByLibrary.simpleMessage("分享串或二维码无效"),
    "week_num_invalid_dialog_content": MessageLookupByLibrary.simpleMessage(
      "课程结束周数应大于起始周数",
    ),
    "week_num_invalid_dialog_title": MessageLookupByLibrary.simpleMessage(
      "课程周数不合法",
    ),
  };
}
