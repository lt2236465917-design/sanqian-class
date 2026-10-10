// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class S {
  S();

  static S? _current;

  static S get current {
    assert(
      _current != null,
      'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.',
    );
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = S();
      S._current = instance;

      return instance;
    });
  }

  static S of(BuildContext context) {
    final instance = S.maybeOf(context);
    assert(
      instance != null,
      'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?',
    );
    return instance!;
  }

  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  /// `导入课表`
  String get import_from_qrcode_title {
    return Intl.message(
      '导入课表',
      name: 'import_from_qrcode_title',
      desc: '',
      args: [],
    );
  }

  /// `分享串或二维码无效`
  String get qrcode_url_error_toast {
    return Intl.message(
      '分享串或二维码无效',
      name: 'qrcode_url_error_toast',
      desc: '',
      args: [],
    );
  }

  /// `读取课程表，可能是 bug`
  String get qrcode_read_error_toast {
    return Intl.message(
      '读取课程表，可能是 bug',
      name: 'qrcode_read_error_toast',
      desc: '',
      args: [],
    );
  }

  /// `相册导入二维码`
  String get qr_scan_from_gallery_button {
    return Intl.message(
      '相册导入二维码',
      name: 'qr_scan_from_gallery_button',
      desc: '',
      args: [],
    );
  }

  /// `从剪贴板导入`
  String get qr_scan_from_clipboard_button {
    return Intl.message(
      '从剪贴板导入',
      name: 'qr_scan_from_clipboard_button',
      desc: '',
      args: [],
    );
  }

  /// `二维码协议版本不支持`
  String get qr_error_unsupported_protocol {
    return Intl.message(
      '二维码协议版本不支持',
      name: 'qr_error_unsupported_protocol',
      desc: '',
      args: [],
    );
  }

  /// `二维码数据校验失败`
  String get qr_error_checksum_mismatch {
    return Intl.message(
      '二维码数据校验失败',
      name: 'qr_error_checksum_mismatch',
      desc: '',
      args: [],
    );
  }

  /// `二维码数据损坏`
  String get qr_error_payload_corrupted {
    return Intl.message(
      '二维码数据损坏',
      name: 'qr_error_payload_corrupted',
      desc: '',
      args: [],
    );
  }

  /// `复制完整分享串`
  String get qr_share_copy_button {
    return Intl.message(
      '复制完整分享串',
      name: 'qr_share_copy_button',
      desc: '',
      args: [],
    );
  }

  /// `已复制完整分享串`
  String get qr_share_copy_success_toast {
    return Intl.message(
      '已复制完整分享串',
      name: 'qr_share_copy_success_toast',
      desc: '',
      args: [],
    );
  }

  /// `导出课程表`
  String get export_title {
    return Intl.message('导出课程表', name: 'export_title', desc: '', args: []);
  }

  /// `确认`
  String get ok {
    return Intl.message('确认', name: 'ok', desc: '', args: []);
  }

  /// `取消`
  String get cancel {
    return Intl.message('取消', name: 'cancel', desc: '', args: []);
  }

  /// `添加课程`
  String get add_manually_title {
    return Intl.message('添加课程', name: 'add_manually_title', desc: '', args: []);
  }

  /// `课程名称`
  String get class_name {
    return Intl.message('课程名称', name: 'class_name', desc: '', args: []);
  }

  /// `请输入课程名称`
  String get class_name_empty {
    return Intl.message(
      '请输入课程名称',
      name: 'class_name_empty',
      desc: '',
      args: [],
    );
  }

  /// `上课老师`
  String get class_teacher {
    return Intl.message('上课老师', name: 'class_teacher', desc: '', args: []);
  }

  /// `上课地点`
  String get class_room {
    return Intl.message('上课地点', name: 'class_room', desc: '', args: []);
  }

  /// `备注`
  String get class_info {
    return Intl.message('备注', name: 'class_info', desc: '', args: []);
  }

  /// `添加课程`
  String get add_class {
    return Intl.message('添加课程', name: 'add_class', desc: '', args: []);
  }

  /// `请输入课程表名称`
  String get add_class_table_dialog_title {
    return Intl.message(
      '请输入课程表名称',
      name: 'add_class_table_dialog_title',
      desc: '',
      args: [],
    );
  }

  /// `课程结束节数应大于起始节数`
  String get class_num_invalid_dialog_content {
    return Intl.message(
      '课程结束节数应大于起始节数',
      name: 'class_num_invalid_dialog_content',
      desc: '',
      args: [],
    );
  }

  /// `课程周数不合法`
  String get week_num_invalid_dialog_title {
    return Intl.message(
      '课程周数不合法',
      name: 'week_num_invalid_dialog_title',
      desc: '',
      args: [],
    );
  }

  /// `已接收 {received}/{total}`
  String qr_scan_parts_received_toast(Object received, Object total) {
    return Intl.message(
      '已接收 $received/$total',
      name: 'qr_scan_parts_received_toast',
      desc: '',
      args: [received, total],
    );
  }

  /// `第 {start}-{end} 节`
  String class_duration(Object start, Object end) {
    return Intl.message(
      '第 $start-$end 节',
      name: 'class_duration',
      desc: '',
      args: [start, end],
    );
  }

  /// `课程节数不合法`
  String get class_num_invalid_dialog_title {
    return Intl.message(
      '课程节数不合法',
      name: 'class_num_invalid_dialog_title',
      desc: '',
      args: [],
    );
  }

  /// `课程结束周数应大于起始周数`
  String get week_num_invalid_dialog_content {
    return Intl.message(
      '课程结束周数应大于起始周数',
      name: 'week_num_invalid_dialog_content',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<S> load(Locale locale) => S.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
