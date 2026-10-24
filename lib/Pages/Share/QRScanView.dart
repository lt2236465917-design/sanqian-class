import 'dart:async';

import '../../generated/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart';

import '../../Components/Toast.dart';
import '../../Components/ScheduleFeedbackNotice.dart';
import 'qr_payload_codec.dart';
import '../../Utils/ScheduleCalendarExporter.dart';

class QRScanView extends StatefulWidget {
  const QRScanView({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _QRScanViewState();
}

class _QRScanViewState extends State<QRScanView> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController();

  final Map<String, _MultiGroupBuffer> _groups = <String, _MultiGroupBuffer>{};
  bool _isCompleting = false;
  bool _scanning = false;
  String? _scanError;
  VoidCallback? _retryScan;

  bool _returningFromSettings = false;
  Future<void> _cameraLifecycle = Future<void>.value();

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scanning || defaultTargetPlatform != TargetPlatform.android) return;
    if (state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive) {
      return;
    }
    _cameraLifecycle = _cameraLifecycle.then((_) async {
      if (!mounted || _isCompleting || _controller.value.isStarting) return;
      try {
        if (state == AppLifecycleState.resumed) {
          // A permission dialog also resumes the app. Do not ask again after denial.
          if (!_controller.value.hasCameraPermission &&
              !_returningFromSettings) {
            return;
          }
          _returningFromSettings = false;
          await _controller.start();
        } else {
          await _controller.stop();
        }
      } catch (_) {
        if (mounted && state == AppLifecycleState.resumed) {
          _showError('相机暂不可用，请检查权限后重试。');
        }
      }
    });
  }

  void _showError(String message) {
    if (mounted && message != _scanError) setState(() => _scanError = message);
  }

  void _retry() {
    final action = _retryScan;
    setState(() => _scanError = null);
    action?.call();
  }

  @override
  void dispose() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).import_from_qrcode_title)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: [
                if (!_scanning)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_scanner, size: 72),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => setState(() {
                            _scanning = true;
                            _scanError = null;
                            _retryScan = null;
                          }),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('开启相机扫码'),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('也可用下方按钮导入二维码图片或分享串。'),
                        ),
                      ],
                    ),
                  ),
                if (_scanning)
                  MobileScanner(
                    controller: _controller,
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.no_photography_outlined, size: 40),
                            const SizedBox(height: 12),
                            const Text(
                              '相机暂不可用。你仍可从相册选择二维码，或从剪贴板导入分享串。',
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  _returningFromSettings = true;
                                  final opened = await ScheduleCalendarExporter
                                      .settingsChannel
                                      .invokeMethod<bool>('openAppSettings');
                                  if (opened != true) {
                                    _returningFromSettings = false;
                                    if (mounted) {
                                      _showError('请在系统设置中允许相机访问。');
                                    }
                                  }
                                } catch (_) {
                                  _returningFromSettings = false;
                                  if (mounted) {
                                    _showError('请在系统设置中允许相机访问。');
                                  }
                                }
                              },
                              child: const Text('打开系统设置'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    onDetect: (BarcodeCapture capture) {
                      if (_scanError != null) return;
                      _retryScan = null;
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final raw = barcode.rawValue;
                        if (raw == null || raw.isEmpty) {
                          continue;
                        }
                        _handleRaw(raw);
                        if (_scanError != null || _isCompleting) break;
                      }
                    },
                  ),
                if (_scanning)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                ? Theme.of(context).primaryColor
                                : Colors.white,
                            width: 4,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_scanError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ScheduleInlineFeedback(
                message: _scanError!,
                actionLabel: _retryScan == null ? '继续扫码' : '重试',
                onAction: _retry,
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _pickFromGallery,
                      child: Text(S.of(context).qr_scan_from_gallery_button),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _importFromClipboard,
                      child: Text(S.of(context).qr_scan_from_clipboard_button),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromClipboard() async {
    setState(() {
      _scanError = null;
      _retryScan = _importFromClipboard;
    });
    ClipboardData? data;
    try {
      data = await Clipboard.getData('text/plain');
    } catch (_) {
      if (mounted) _showError('无法读取剪贴板，请允许粘贴或使用二维码图片。');
      return;
    }
    if (!mounted) return;
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) {
      _showError(S.of(context).qrcode_url_error_toast);
      return;
    }

    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      if (lines.length <= 1) {
        await _handleRaw(text);
      } else {
        String? progress;
        for (final line in lines) {
          await _handleRaw(line, onProgress: (message) => progress = message);
          if (_isCompleting || !mounted || _scanError != null) {
            break;
          }
        }
        // Process the whole pasted batch before showing an incomplete result.
        if (mounted &&
            !_isCompleting &&
            _scanError == null &&
            ModalRoute.of(context)?.isCurrent == true &&
            progress != null) {
          Toast.showToast(progress!, context);
        }
      }
    } catch (_) {
      if (!mounted) return;
      _showError(S.of(context).qrcode_url_error_toast);
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() {
      _scanError = null;
      _retryScan = _pickFromGallery;
    });
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.gallery);
    } catch (_) {
      if (mounted) _showError('无法打开相册，请检查照片权限。');
      return;
    }
    if (!mounted) return;
    if (file == null) {
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _showError(S.of(context).qrcode_url_error_toast);
        return;
      }

      final pixels = Int32List(decoded.width * decoded.height);
      int i = 0;
      for (int y = 0; y < decoded.height; y++) {
        for (int x = 0; x < decoded.width; x++) {
          final p = decoded.getPixel(x, y);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          pixels[i++] = (0xFF << 24) | (r << 16) | (g << 8) | b;
        }
      }

      final source = RGBLuminanceSource(decoded.width, decoded.height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final result = QRCodeReader().decode(bitmap);
      final text = result.text;
      if (text.isEmpty) {
        _showError(S.of(context).qrcode_url_error_toast);
        return;
      }
      await _handleRaw(text);
    } catch (_) {
      _showError(S.of(context).qrcode_url_error_toast);
    }
  }

  Future<void> _handleRaw(
    String raw, {
    ValueChanged<String>? onProgress,
  }) async {
    if (_isCompleting ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    if (!QrPayloadCodec.isNcsQrPayload(raw)) {
      _showError(S.of(context).qrcode_url_error_toast);
      return;
    }

    final parsed = QrPayloadCodec.parseFrame(raw);
    if (parsed == null) {
      _showError(S.of(context).qrcode_url_error_toast);
      return;
    }

    if (_scanError != null) setState(() => _scanError = null);
    if (parsed.kind == QrFrameKind.single) {
      await _decodeAndFinish(parsed.payload);
      return;
    }

    final groupId = parsed.groupId!;
    final buffer = _groups.putIfAbsent(
      groupId,
      () => _MultiGroupBuffer(total: parsed.total!),
    );
    buffer.touch();
    // Announce each new QR part once, even if the camera keeps seeing it.
    if (onProgress == null && buffer.parts[parsed.index!] == parsed.payload) {
      return;
    }
    buffer.parts[parsed.index!] = parsed.payload;
    _cleanupExpiredGroups();

    final merged = QrPayloadCodec.mergeEncodedPayloadParts(
      buffer.parts,
      buffer.total,
    );
    if (merged == null) {
      final message = S
          .of(context)
          .qr_scan_parts_received_toast(buffer.parts.length, buffer.total);
      if (onProgress != null) {
        onProgress(message);
      } else {
        Toast.showToast(message, context);
      }
      return;
    }

    await _decodeAndFinish(merged);
  }

  Future<void> _decodeAndFinish(String encodedPayload) async {
    try {
      _isCompleting = true;
      final decoded = QrPayloadCodec.decodeEncodedPayload(encodedPayload);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      Navigator.of(context).pop(decoded);
    } catch (e) {
      _isCompleting = false;
      _showError(_readableError(e));
    }
  }

  void _cleanupExpiredGroups() {
    final now = DateTime.now();
    final expired = <String>[];
    _groups.forEach((key, value) {
      if (now.difference(value.updatedAt).inMinutes >= 2) {
        expired.add(key);
      }
    });
    for (final key in expired) {
      _groups.remove(key);
    }
  }

  String _readableError(Object error) {
    if (error is FormatException) {
      final code = error.message;
      if (code == 'unsupported_payload_type' ||
          code == 'unsupported_payload_version' ||
          code == 'unsupported_payload_algorithm') {
        return S.of(context).qr_error_unsupported_protocol;
      }
      if (code == 'checksum_mismatch') {
        return S.of(context).qr_error_checksum_mismatch;
      }
      if (code == 'base64_decode_failed' || code == 'gzip_decode_failed') {
        return S.of(context).qr_error_payload_corrupted;
      }
    }
    return S.of(context).qrcode_read_error_toast;
  }
}

class _MultiGroupBuffer {
  final int total;
  final Map<int, String> parts = <int, String>{};
  DateTime updatedAt = DateTime.now();

  _MultiGroupBuffer({required this.total});

  void touch() {
    updatedAt = DateTime.now();
  }
}
