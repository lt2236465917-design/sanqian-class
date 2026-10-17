import 'package:flutter/material.dart';
import 'ScheduleFeedbackNotice.dart';

class Toast {
  static void showToast(String text, BuildContext context) =>
      ScheduleFeedbackNotice.show(context, text, bottomSpacing: 88);
}
