import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;
    final email = user?.email ?? '';
    final role = user?.role ?? 'customer';
    final initial = email.isEmpty ? 'Q' : email.characters.first.toUpperCase();

    return CustomerShell(
      navIndex: 4,
      title: 'Profile',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: AppColors.forest,
                        child: Text(initial,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26)),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email.isEmpty ? 'Signed in' : email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Pill(
                              label: role == 'admin' ? 'Administrator' : 'Customer',
                              icon: role == 'admin' ? Icons.shield_outlined : Icons.person_outline_rounded,
                              color: role == 'admin' ? AppColors.forest : AppColors.info,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Account'),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _MenuTile(
                        icon: Icons.receipt_long_outlined,
                        label: 'My orders',
                        subtitle: 'Track and revisit past orders',
                        onTap: () => context.go('/orders'),
                      ),
                      const Divider(height: 1, indent: 64),
                      _MenuTile(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notifications',
                        subtitle: 'Order updates and status changes',
                        onTap: () => context.push('/notifications'),
                      ),
                      const Divider(height: 1, indent: 64),
                      _MenuTile(
                        icon: Icons.shopping_bag_outlined,
                        label: 'Your cart',
                        subtitle: 'Items waiting to be checked out',
                        onTap: () => context.go('/cart'),
                      ),
                      if (role == 'admin') ...[
                        const Divider(height: 1, indent: 64),
                        _MenuTile(
                          icon: Icons.dashboard_outlined,
                          label: 'Admin dashboard',
                          subtitle: 'KPIs, analytics and order management',
                          onTap: () => context.go('/admin'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const BrandMark(size: 36),
                          const SizedBox(width: AppSpacing.md),
                          Text('QuickBitee', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'A demo food-ordering platform built with Flutter, FastAPI, PostgreSQL and RabbitMQ. Orders, payments and notifications are simulated end-to-end.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                          icon: const Icon(Icons.logout_rounded, size: 19),
                          label: const Text('Sign out'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.subtitle, required this.onTap});

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      leading: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(color: AppColors.limeSoft, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: AppColors.forest),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
