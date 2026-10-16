import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

/// Offers page.
///
/// QuickBitee stores no promotions of its own, so this screen renders whatever
/// the API configures — labelled honestly. Every development-only entry carries
/// a "Demo offer" badge and its disclosure (no discount at checkout) is printed
/// in full; when nothing is configured the page says so instead of inventing a
/// deal.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  Promotions _promotions = const Promotions();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).promotions();
      if (!mounted) return;
      setState(() => _promotions = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offers = _promotions.offers;
    return CustomerShell(
      navIndex: null,
      showBack: true,
      title: 'Offers',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ContentWidth(
              maxWidth: 1100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Text('Offers & spotlights',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Promotions configured for QuickBitee. Demo entries are '
                    'clearly badged and never change what you pay at checkout.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_error != null)
                    ErrorState(message: _error!, onRetry: _load)
                  else if (_loading)
                    ResponsiveWrap(
                      minItemWidth: 320,
                      children: List.generate(
                          2, (_) => const SkeletonCard(imageHeight: 160)),
                    )
                  else if (offers.isEmpty)
                    const AppCard(
                      child: EmptyState(
                        icon: Icons.local_offer_outlined,
                        title: 'No offers right now',
                        subtitle:
                            'There are no promotions configured at the moment. '
                            'Check back later — we only show real offers.',
                      ),
                    )
                  else
                    ResponsiveWrap(
                      minItemWidth: 320,
                      children: [
                        for (final offer in offers) _OfferCard(offer: offer),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AppImage(
                url: offer.imageUrl,
                aspectRatio: 16 / 9,
                fallbackIcon: Icons.local_offer_outlined,
              ),
              if ((offer.badge ?? '').isNotEmpty)
                Positioned(
                  left: AppSpacing.md,
                  top: AppSpacing.md,
                  child: Pill(
                    label: offer.badge!,
                    icon: Icons.info_outline_rounded,
                    color: AppColors.forestDeep,
                    background: AppColors.lime,
                    dense: true,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(offer.description,
                    style: Theme.of(context).textTheme.bodySmall),
                if ((offer.disclosure ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.creamDeep,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 15, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            offer.disclosure!,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () {
                    final target = offer.target.trim();
                    context.go(target.isEmpty ? '/explore' : target);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.forest,
                    minimumSize: const Size(0, 46),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(offer.ctaLabel.isEmpty
                      ? 'Browse restaurants'
                      : offer.ctaLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
