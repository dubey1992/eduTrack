import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/failure.dart';
import '../theme/app_colors.dart';

/// Renders an [AsyncValue] with the app's standard loading / error / data
/// states, so every API-driven screen behaves consistently (see backend
/// CLAUDE.md rule 7 - never a blank screen on failure, retry where useful).
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.emptyBuilder,
    this.isEmpty,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) data;
  final VoidCallback? onRetry;
  final WidgetBuilder? emptyBuilder;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      ),
      error: (error, _) => _ErrorView(failure: _asFailure(error), onRetry: onRetry),
      data: (value) {
        if (isEmpty != null && emptyBuilder != null && isEmpty!(value)) {
          return emptyBuilder!(context);
        }
        return data(context, value);
      },
    );
  }

  Failure _asFailure(Object error) => error is Failure ? error : Failure.unknown(error.toString());
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 36),
            const SizedBox(height: 12),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
