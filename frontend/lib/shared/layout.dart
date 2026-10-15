import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/auth_controller.dart';
import '../state/cart_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Constrains page content to a comfortable reading width and applies
/// breakpoint-aware horizontal gutters. Prevents over-wide layouts on desktop.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 1200, this.padding});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = AppBreakpoints.isDesktop(width)
        ? AppSpacing.xxl
        : AppBreakpoints.isTablet(width)
            ? AppSpacing.xl
            : AppSpacing.lg;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: gutter),
          child: child,
        ),
      ),
    );
  }
}

/// Lays children out in a responsive wrapped grid: as many columns of at least
/// [minItemWidth] as fit, evenly spaced.
class ResponsiveWrap extends StatelessWidget {
  const ResponsiveWrap({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.spacing = AppSpacing.lg,
    this.runSpacing = AppSpacing.lg,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        var columns = ((available + spacing) / (minItemWidth + spacing)).floor();
        if (columns < 1) columns = 1;
        final itemWidth = (available - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// The five customer destinations in bottom / top navigation.
class _Destination {
  const _Destination(this.label, this.icon, this.activeIcon, this.route);
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;
}

const _destinations = [
  _Destination('Home', Icons.home_outlined, Icons.home_rounded, '/'),
  _Destination('Explore', Icons.explore_outlined, Icons.explore_rounded, '/explore'),
  _Destination('Cart', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, '/cart'),
  _Destination('Orders', Icons.receipt_long_outlined, Icons.receipt_long_rounded, '/orders'),
  _Destination('Profile', Icons.person_outline_rounded, Icons.person_rounded, '/profile'),
];

/// Shared page chrome: a desktop top navigation bar, or a mobile app bar plus
/// bottom navigation. Every authenticated customer screen uses this so the
/// header, cart badge and navigation behave identically everywhere.
class CustomerShell extends ConsumerWidget {
  const CustomerShell({
    super.key,
    required this.body,
    this.navIndex,
    this.title,
    this.actions = const [],
    this.floatingActionButton,
    this.showBack = false,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor = AppColors.cream,
  });

  final Widget body;
  final int? navIndex;
  final String? title;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final bool showBack;
  final bool resizeToAvoidBottomInset;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = AppBreakpoints.isDesktop(width);
    final cartQty = ref.watch(cartProvider.select((c) => c.totalQuantity));

    if (isDesktop) {
      return Scaffold(
        backgroundColor: backgroundColor,
        floatingActionButton: floatingActionButton,
        body: Column(
          children: [
            _DesktopNav(navIndex: navIndex, cartQty: cartQty, showBack: showBack),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
              )
            : null,
        titleSpacing: showBack ? 0 : AppSpacing.lg,
        title: title == null
            ? BrandLogo(size: 32, onTap: () => context.go('/'))
            : Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [...actions, const SizedBox(width: AppSpacing.xs)],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: navIndex == null
          ? null
          : _MobileBottomNav(index: navIndex!, cartQty: cartQty),
    );
  }
}

class _DesktopNav extends ConsumerWidget {
  const _DesktopNav({required this.navIndex, required this.cartQty, required this.showBack});

  final int? navIndex;
  final int cartQty;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final role = user is SignedIn ? user.user.role : 'customer';
    final email = user is SignedIn ? user.user.email : '';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: ContentWidth(
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                BrandLogo(size: 34, onTap: () => context.go('/')),
                const SizedBox(width: AppSpacing.xl),
                for (var i = 0; i < _destinations.length; i++)
                  if (_destinations[i].route != '/cart')
                    _NavLink(
                      label: _destinations[i].label,
                      selected: navIndex == i,
                      onTap: () => context.go(_destinations[i].route),
                    ),
                const Spacer(),
                // Shrinkable so the header never overflows on narrower desktops.
                Flexible(child: _HeaderSearch()),
                const SizedBox(width: AppSpacing.md),
                _IconAction(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notifications',
                  onTap: () => context.push('/notifications'),
                ),
                _CartAction(cartQty: cartQty, onTap: () => context.go('/cart')),
                const SizedBox(width: AppSpacing.sm),
                _ProfileMenu(email: email, role: role),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Material(
        color: selected ? AppColors.limeSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: selected ? AppColors.forestDeep : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderSearch extends StatefulWidget {
  @override
  State<_HeaderSearch> createState() => _HeaderSearchState();
}

class _HeaderSearchState extends State<_HeaderSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _controller.text.trim();
    context.go(q.isEmpty ? '/explore' : '/explore?q=${Uri.encodeComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 44,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search dishes or restaurants',
          fillColor: AppColors.cream,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: const BorderSide(color: AppColors.forest, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}

class _CartAction extends StatelessWidget {
  const _CartAction({required this.cartQty, required this.onTap});

  final int cartQty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_bag_rounded, size: 19, color: AppColors.forestDeep),
                if (cartQty > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$cartQty',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.forestDeep,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.email, required this.role});

  final String email;
  final String role;

  @override
  Widget build(BuildContext context) {
    final initial = email.isEmpty ? 'Q' : email.characters.first.toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      onSelected: (value) {
        switch (value) {
          case 'profile':
            context.go('/profile');
          case 'orders':
            context.go('/orders');
          case 'notifications':
            context.push('/notifications');
          case 'admin':
            context.go('/admin');
          case 'logout':
            ProviderScope.containerOf(context).read(authControllerProvider.notifier).logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(role == 'admin' ? 'Administrator' : 'Customer',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'profile', child: _MenuRow(Icons.person_outline_rounded, 'Profile')),
        const PopupMenuItem(value: 'orders', child: _MenuRow(Icons.receipt_long_outlined, 'My orders')),
        const PopupMenuItem(value: 'notifications', child: _MenuRow(Icons.notifications_none_rounded, 'Notifications')),
        if (role == 'admin')
          const PopupMenuItem(value: 'admin', child: _MenuRow(Icons.dashboard_outlined, 'Admin dashboard')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: _MenuRow(Icons.logout_rounded, 'Sign out')),
      ],
      child: CircleAvatar(
        radius: 19,
        backgroundColor: AppColors.forest,
        child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [Icon(icon, size: 19), const SizedBox(width: 10), Text(label)],
      );
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({required this.index, required this.cartQty});

  final int index;
  final int cartQty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _destinations.length; i++)
                Expanded(
                  child: _BottomItem(
                    destination: _destinations[i],
                    selected: index == i,
                    badgeCount: _destinations[i].route == '/cart' ? cartQty : 0,
                    onTap: () => context.go(_destinations[i].route),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.destination,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.forest : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badgeCount > 0,
            label: Text('$badgeCount'),
            backgroundColor: AppColors.forest,
            child: Icon(selected ? destination.activeIcon : destination.icon, color: color, size: 24),
          ),
          const SizedBox(height: 3),
          Text(
            destination.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
