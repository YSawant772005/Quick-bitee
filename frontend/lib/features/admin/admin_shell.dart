import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme.dart';
import '../../state/admin_range_controller.dart';
import '../../state/auth_controller.dart';
import 'admin_widgets.dart';

/// One sidebar entry.
///
/// The list only contains modules that actually exist in this build. Anything
/// the backend cannot back (offers/coupons, reviews) is deliberately absent so
/// the sidebar never offers a route to an empty page — see the completion
/// report for the documented gaps.
class AdminNavItem {
  const AdminNavItem(this.label, this.route, this.icon, this.activeIcon);

  final String label;
  final String route;
  final IconData icon;
  final IconData activeIcon;

  bool matches(String location) =>
      route == '/admin' ? location == '/admin' : location == route || location.startsWith('$route/');
}

const adminNavItems = [
  AdminNavItem('Overview', '/admin', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  AdminNavItem('Orders', '/admin/orders', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  AdminNavItem('Restaurants', '/admin/restaurants', Icons.storefront_outlined, Icons.storefront_rounded),
  AdminNavItem('Menu Management', '/admin/menu', Icons.menu_book_outlined, Icons.menu_book_rounded),
  AdminNavItem('Customers', '/admin/customers', Icons.groups_outlined, Icons.groups_rounded),
  AdminNavItem('Deliveries', '/admin/deliveries', Icons.delivery_dining_outlined, Icons.delivery_dining_rounded),
  AdminNavItem('Analytics', '/admin/analytics', Icons.insights_outlined, Icons.insights_rounded),
  AdminNavItem('Settings', '/admin/settings', Icons.settings_outlined, Icons.settings_rounded),
];

/// Resolves the current location into its sidebar entry (falls back to
/// Overview for unknown admin sub-routes).
AdminNavItem adminNavItemFor(String location) {
  for (final item in adminNavItems) {
    if (item.matches(location)) return item;
  }
  return adminNavItems.first;
}

/// Title shown in the admin header for a location.
String adminTitleFor(String location) {
  if (location.startsWith('/admin/orders/')) return 'Order details';
  return adminNavItemFor(location).label;
}

/// True for the analytics-shaped screens that own a reporting period.
bool adminShowsDateRange(String location) =>
    location == '/admin' || location.startsWith('/admin/analytics');

/// Application shell for the whole admin console: ink sidebar, operational
/// header, and a drawer below the desktop breakpoint.
///
/// Deliberately shares no chrome with [CustomerShell] — no top nav, no bottom
/// nav, no hero, no cuisine chips.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppBreakpoints.desktop;

    if (wide) {
      return Scaffold(
        backgroundColor: AdminColors.canvas,
        drawer: null,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: AdminLayout.sidebarWidth, child: _Sidebar()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    bottom: false,
                    child: _AdminHeader(title: adminTitleFor(location), location: location, showMenuButton: false),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AdminColors.canvas,
      drawer: const Drawer(
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: SizedBox(width: AdminLayout.sidebarWidth, child: _Sidebar()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: _AdminHeader(title: adminTitleFor(location), location: location, showMenuButton: true),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final email = ref.watch(authControllerProvider.select((s) => s is SignedIn ? s.user.email : ''));
    final width = MediaQuery.sizeOf(context).width;
    final collapsed = width >= AppBreakpoints.desktop && width < AppBreakpoints.desktop + 120;

    return Container(
      color: AdminColors.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AdminColors.brand,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.bolt_rounded, size: 18, color: AdminColors.accent),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QuickBitee',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'OPERATIONS CONSOLE',
                            style: TextStyle(
                              color: AdminColors.sidebarText,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: AdminColors.sidebarLine, indent: 16, endIndent: 16),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final nav in adminNavItems)
                    _SidebarItem(
                      item: nav,
                      selected: nav.matches(location),
                      collapsed: collapsed,
                      onTap: () {
                        context.go(nav.route);
                        // Close the drawer when navigating from a phone/tablet.
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AdminColors.sidebarLine, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.all(10),
              child: collapsed
                  ? IconButton(
                      tooltip: 'Sign out',
                      onPressed: () => _signOut(context),
                      icon: const Icon(Icons.logout_rounded, size: 19, color: AdminColors.sidebarText),
                    )
                  : _SidebarAction(
                      icon: Icons.logout_rounded,
                      label: 'Sign out',
                      email: email,
                      onTap: () => _signOut(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _signOut(BuildContext context) {
    ProviderScope.containerOf(context).read(authControllerProvider.notifier).logout();
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.collapsed,
  });

  final AdminNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: selected ? AdminColors.sidebarActive : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 10),
          child: collapsed
              ? Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 20,
                  color: selected ? AdminColors.accent : AdminColors.sidebarText,
                )
              : Row(
                  children: [
                    Icon(
                      selected ? item.activeIcon : item.icon,
                      size: 18,
                      color: selected ? AdminColors.accent : AdminColors.sidebarText,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected ? Colors.white : AdminColors.sidebarText,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(color: AdminColors.accent, shape: BoxShape.circle),
                      ),
                  ],
                ),
        ),
      ),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 2), child: content);
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({required this.icon, required this.label, required this.onTap, this.email});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AdminColors.sidebarText),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (email != null && email!.isNotEmpty)
                      Text(
                        email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AdminColors.sidebarText),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _AdminHeader extends ConsumerWidget {
  const _AdminHeader({
    required this.title,
    required this.location,
    required this.showMenuButton,
  });

  final String title;
  final String location;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authControllerProvider.select((s) => s is SignedIn ? s.user.email : ''));
    final showRange = adminShowsDateRange(location);
    final narrow = MediaQuery.sizeOf(context).width < AppBreakpoints.desktop;

    return Container(
      color: AdminColors.canvas,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showMenuButton)
                IconButton(
                  tooltip: 'Open navigation',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              if (showMenuButton) const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AdminColors.inkMuted,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.chevron_right_rounded, size: 13, color: AdminColors.inkMuted),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showRange) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reporting period · ${ref.watch(adminRangeProvider).label}',
                        style: AdminType.caption,
                      ),
                    ],
                  ],
                ),
              ),
              if (showRange) ...[
                if (!narrow) ...[
                  const DateRangeControl(),
                  const SizedBox(width: AppSpacing.lg),
                ] else ...[
                  IconButton(
                    tooltip: 'Reporting period: ${ref.watch(adminRangeProvider).label}',
                    onPressed: () => _showRangeSheet(context, ref),
                    icon: const Icon(Icons.date_range_rounded, size: 20),
                  ),
                ],
              ],
              _AdminProfileMenu(email: email),
            ],
          ),
          if (showRange && narrow) ...[
            const SizedBox(height: 10),
            // The compact period switcher (a segmented control) cannot shrink
            // its own segments; let it scroll sideways so it stays reachable on
            // the narrowest phones instead of clipping.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: const DateRangeControl(compact: true),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1, color: AdminColors.line),
        ],
      ),
    );
  }

  void _showRangeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AdminColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reporting period', style: AdminType.sectionTitle),
              const SizedBox(height: AppSpacing.md),
              // Scrollable so the segmented control stays usable even on a
              // narrow phone inside the sheet.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: const DateRangeControl(),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminProfileMenu extends ConsumerWidget {
  const _AdminProfileMenu({required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = email.isEmpty ? 'A' : email.characters.first.toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        switch (value) {
          case 'customer':
            context.go('/');
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
              Text(email, style: const TextStyle(fontWeight: FontWeight.w700, color: AdminColors.ink)),
              const Text('Administrator',
                  style: TextStyle(color: AdminColors.inkSoft, fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'customer',
          child: Row(children: [Icon(Icons.storefront_outlined, size: 18), SizedBox(width: 10), Text('Customer app')]),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [Icon(Icons.logout_rounded, size: 18), SizedBox(width: 10), Text('Sign out')]),
        ),
      ],
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(color: AdminColors.brand, shape: BoxShape.circle),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
