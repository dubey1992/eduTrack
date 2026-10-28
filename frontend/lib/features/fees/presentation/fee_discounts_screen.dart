import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/student_fees_providers.dart';
import '../data/models/student_fees.dart';
import '../data/money_text.dart';
import 'widgets/adjustment_actions.dart';

/// Every discount the school has given (docs/fees.md, F4): who, how much, on
/// what, and why. Discounts are added from a student's page; here they can
/// be reviewed and ended.
class FeeDiscountsScreen extends ConsumerStatefulWidget {
  const FeeDiscountsScreen({super.key});

  @override
  ConsumerState<FeeDiscountsScreen> createState() => _FeeDiscountsScreenState();
}

class _FeeDiscountsScreenState extends ConsumerState<FeeDiscountsScreen> {
  int? _schoolId;
  bool _includeEnded = false;
  int _page = 1;
  int _perPage = 20;

  void _filter(VoidCallback change) => setState(() {
    change();
    _page = 1;
  });

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    final mustPickSchool = actor?.picksSchool ?? false;
    final canManage = actor != null && actor.role != UserRole.superAdmin && actor.canManage(AppModules.fees);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Discounts',
          actions: [
            SchoolFilterDropdown(selected: _schoolId, onChanged: (schoolId) => _filter(() => _schoolId = schoolId)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Discounts are added from a student\'s page under Student Fees.',
                style: TextStyle(color: context.appColors.muted),
              ),
              FilterChip(
                label: const Text('Show ended ones'),
                selected: _includeEnded,
                onSelected: (value) => _filter(() => _includeEnded = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: mustPickSchool && _schoolId == null
              ? _Prompt(
                  message: actor?.role == UserRole.superAdmin
                      ? 'Choose a school to see its discounts.'
                      : 'Choose a branch to see its discounts.',
                )
              : _list(canManage),
        ),
      ],
    );
  }

  Widget _list(bool canManage) {
    final query = (
      schoolId: _schoolId,
      academicYearId: null,
      includeRevoked: _includeEnded,
      page: _page,
      perPage: _perPage,
    );

    return AsyncValueView<PaginatedResponse<FeeConcession>>(
      value: ref.watch(feeConcessionsProvider(query)),
      onRetry: () => ref.invalidate(feeConcessionsProvider(query)),
      isEmpty: (page) => page.items.isEmpty,
      emptyBuilder: (context) => const _Prompt(message: 'No discount has been given yet.'),
      data: (context, page) => Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _DiscountCard(concession: page.items[index], canManage: canManage),
            ),
          ),
          PaginationControls(
            currentPage: page.currentPage,
            lastPage: page.lastPage,
            total: page.total,
            perPage: page.perPage,
            onPageChanged: (value) => setState(() => _page = value),
            onPerPageChanged: (value) => _filter(() => _perPage = value),
          ),
        ],
      ),
    );
  }
}

class _DiscountCard extends ConsumerWidget {
  const _DiscountCard({required this.concession, required this.canManage});

  final FeeConcession concession;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final amount = concession.isPercent
        ? '${concession.value}%'
        : formatCurrency((centsOf(concession.value) ?? 0) / 100, concession.currencyCode);
    final created = concession.createdAt;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$amount off each ${concession.feeHeadName ?? 'fee'} installment',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (concession.isRevoked) const StatusBadge(label: 'Ended', tone: BadgeTone.neutral),
                    ],
                  ),
                  InkWell(
                    onTap: () => context.go('/student-fees?student=${concession.studentId}'),
                    child: Text(
                      [
                        concession.studentName,
                        concession.admissionNumber,
                        ?concession.className,
                        concession.academicYearName,
                      ].join(' · '),
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
                    ),
                  ),
                  Text(
                    [
                      concession.reason,
                      if (concession.createdByName != null) 'by ${concession.createdByName}',
                      if (created != null) formatDate(created),
                    ].join(' · '),
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ),
              if (canManage && !concession.isRevoked)
                TextButton(
                  onPressed: () => revokeDiscount(context, ref, concession),
                  child: const Text('End discount'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.appColors.muted),
        ),
      ),
    );
  }
}
