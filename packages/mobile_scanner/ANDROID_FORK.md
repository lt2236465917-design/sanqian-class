# Android recognition fork

Based on mobile_scanner 7.1.3 (BSD-3-Clause). `darwin/` is byte-for-byte upstream. The Dart method-channel adapter adds Android-only pending-start cancellation; other Dart sources are unchanged; Android retains CameraX and the existing Flutter channels, replacing ML Kit with ZXing-C++ 3.0.2 (Apache-2.0). CameraX is 1.5.2 to match ZXing-C++.

This app uses QR payload text only. Android supports QR decoding with normal/manual zoom, torch, scan window and returned image; structured barcode contact/payment fields and ML Kit auto-zoom are not supplied. The app does not request those fields or auto-zoom. Gallery import remains Dart image/zxing2. No model download or fallback.
