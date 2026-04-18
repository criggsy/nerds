import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full error text in a scrollable, selectable dialog (toasts truncate long messages).
Future<void> showAppErrorDialog(
  BuildContext context,
  String message, {
  String title = 'Something went wrong',
}) async {
  final text = message.trim().isEmpty ? 'Unknown error' : message.trim();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            }
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
