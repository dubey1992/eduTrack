import 'package:flutter/material.dart';

/// Prev/next paging plus a "rows per page" selector, shared across every
/// paginated list screen so they all page the same way (backend CLAUDE.md
/// rule 12 - lists are always paginated server-side, this is its UI).
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.perPage,
    required this.onPageChanged,
    required this.onPerPageChanged,
  });

  final int currentPage;
  final int lastPage;
  final int total;
  final int perPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPerPageChanged;

  static const perPageOptions = [10, 20, 50, 100];

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();

    final mutedStyle = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final from = (currentPage - 1) * perPage + 1;
    final to = ((currentPage - 1) * perPage + perPage).clamp(from, total);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text('Showing $from-$to of $total', style: mutedStyle),
          Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Rows per page', style: mutedStyle),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: perPageOptions.contains(perPage) ? perPage : perPageOptions.first,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final option in perPageOptions) DropdownMenuItem(value: option, child: Text('$option')),
                    ],
                    onChanged: (value) {
                      if (value != null) onPerPageChanged(value);
                    },
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous page',
                    visualDensity: VisualDensity.compact,
                    onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
                  ),
                  Text('Page $currentPage of $lastPage', style: mutedStyle),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next page',
                    visualDensity: VisualDensity.compact,
                    onPressed: currentPage < lastPage ? () => onPageChanged(currentPage + 1) : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
