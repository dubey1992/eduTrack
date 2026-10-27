import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../application/site_page_notifiers.dart';
import '../data/models/site_page.dart';
import '../data/site_page_repository.dart';
import 'widgets/page_text_view.dart';

/// A website page - About Us, Privacy Policy, Terms of Use, or one the
/// Super Admin added (docs/site-pages.md).
///
/// Public on purpose, like the homepage: a privacy policy has to be
/// readable by a parent, a Play reviewer or a school's lawyer, none of whom
/// have an account. So it lives outside the signed-in shell.
class SitePageScreen extends ConsumerWidget {
  const SitePageScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(publishedSitePageProvider(slug));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Homepage',
          onPressed: () => context.go('/'),
        ),
        title: const Text('School365ai'),
      ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is Failure && error.code == SitePageRepository.notFoundCode) return const _NotAvailable();

          return _CouldNotLoad(
            message: error is Failure ? error.message : 'Something went wrong. Please try again.',
            onRetry: () => ref.invalidate(publishedSitePageProvider(slug)),
          );
        },
        data: (page) => _Page(page: page),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.page});

  final SitePage page;

  @override
  Widget build(BuildContext context) {
    final publishedAt = page.publishedAt;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          children: [
            Text(page.title, style: Theme.of(context).textTheme.headlineMedium),
            if (publishedAt != null) ...[
              const SizedBox(height: 4),
              Text('Last updated ${formatDate(publishedAt)}', style: TextStyle(color: context.appColors.muted)),
            ],
            const SizedBox(height: 16),
            PageTextView(text: page.body),
          ],
        ),
      ),
    );
  }
}

/// Unknown, deleted or not published yet - all the same to a visitor.
class _NotAvailable extends StatelessWidget {
  const _NotAvailable();

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.description_outlined,
      title: 'This page is not available',
      body: 'It may have moved, or it has not been published yet.',
      action: FilledButton(onPressed: () => context.go('/'), child: const Text('Go to the homepage')),
    );
  }
}

class _CouldNotLoad extends StatelessWidget {
  const _CouldNotLoad({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.cloud_off_outlined,
      title: 'This page could not be loaded',
      body: message,
      action: FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, required this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.appColors.muted),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted),
            ),
            const SizedBox(height: 20),
            action,
          ],
        ),
      ),
    );
  }
}
