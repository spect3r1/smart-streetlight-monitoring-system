import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.tint,
    this.trailing,
  });

  final String label;
  final String value;
  final String caption;
  final Color tint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.insights_rounded, color: tint),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 18),
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 10),
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(caption, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
