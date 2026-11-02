import 'package:flutter/material.dart';

/// The only button this app uses.
///
/// 96 dp tall, full width, large label, always with a spoken label so
/// TalkBack announces it correctly.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.semanticHint,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        button: true,
        label: label,
        hint: semanticHint,
        excludeSemantics: true,
        child: SizedBox(
          width: double.infinity,
          // 84 dp, not 96: five of these plus Settings have to fit on a
          // 640 dp-tall phone without scrolling. Still far above the 48 dp
          // minimum touch target.
          height: 84,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 34),
                  const SizedBox(width: 14),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
