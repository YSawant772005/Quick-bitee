import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../shared/cards.dart';
import '../../shared/layout.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

enum _SortMode { recommended, az, za, openFirst }

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen(
      {super.key, this.initialQuery = '', this.initialCuisine = ''});

  final String initialQuery;
  final String initialCuisine;

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();

  List<Restaurant> _all = const [];
  List<String> _cuisines = const [];
  String _query = '';
  String _cuisine = '';
  bool _onlyOpen = false;
  _SortMode _sort = _SortMode.recommended;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _cuisine = widget.initialCuisine;
    _searchController.text = widget.initialQuery;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The desktop header search re-navigates to /explore?q=… while Explore may
    // already be mounted, so react to a changed query instead of only initState.
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.initialCuisine != widget.initialCuisine) {
      _query = widget.initialQuery;
      _cuisine = widget.initialCuisine;
      _searchController.text = widget.initialQuery;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).allRestaurants(
            search: _query.isEmpty ? null : _query,
            category: _cuisine.isEmpty ? null : _cuisine,
          );
      final cuisines = <String>{};
      for (final r in data.items) {
        if (r.cuisine.trim().isNotEmpty) cuisines.add(r.cuisine);
      }
      if (!mounted) return;
      setState(() {
        _all = data.items.toList();
        // Keep the cuisine filter list stable once we have seen the full set.
        _cuisines = cuisines.toList()..sort();
        _loading = false;
      });
      if (_cuisine.isEmpty && _cuisines.isEmpty) {
        // Fetch the unfiltered list once so the chips are always populated.
        final all = await ref.read(apiClientProvider).allRestaurants();
        final names = <String>{
          for (final r in all.items)
            if (r.cuisine.trim().isNotEmpty) r.cuisine
        }.toList()
          ..sort();
        if (mounted) setState(() => _cuisines = names);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Restaurant> get _visible {
    final list = List<Restaurant>.from(_all);
    if (_onlyOpen) list.retainWhere((r) => r.available);
    switch (_sort) {
      case _SortMode.az:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _SortMode.za:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case _SortMode.openFirst:
        list.sort((a, b) {
          if (a.available == b.available) return a.name.compareTo(b.name);
          return a.available ? -1 : 1;
        });
      case _SortMode.recommended:
        break;
    }
    return list;
  }

  void _selectCuisine(String cuisine) {
    setState(() => _cuisine = cuisine);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return CustomerShell(
      navIndex: 1,
      title: 'Explore',
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Text('Find your next favourite',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.md),
                  _SearchField(
                    controller: _searchController,
                    onSubmit: () {
                      setState(() => _query = _searchController.text.trim());
                      _load();
                    },
                    onClear: () {
                      _searchController.clear();
                      setState(() => _query = '');
                      _load();
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_cuisines.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            icon: Icons.grid_view_rounded,
                            selected: _cuisine.isEmpty,
                            onTap: () => _selectCuisine(''),
                          ),
                          for (final c in _cuisines)
                            _FilterChip(
                              label: c,
                              selected: _cuisine == c,
                              onTap: () => _selectCuisine(c),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ToggleChip(
                        label: 'Open now',
                        icon: Icons.check_circle_outline_rounded,
                        selected: _onlyOpen,
                        onTap: () => setState(() => _onlyOpen = !_onlyOpen),
                      ),
                      _SortDropdown(
                          value: _sort,
                          onChanged: (v) => setState(() => _sort = v)),
                      Text(
                        _loading
                            ? 'Searching…'
                            : '${visible.length} result${visible.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ErrorState(message: _error!, onRetry: _load),
              )
            else if (_loading)
              ContentWidth(
                child: ResponsiveWrap(
                  minItemWidth: 300,
                  children: List.generate(
                      6, (_) => const SkeletonCard(imageHeight: 168)),
                ),
              )
            else if (visible.isEmpty)
              ContentWidth(
                child: AppCard(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches found',
                    subtitle: _query.isEmpty
                        ? 'Try another category or clear your filters.'
                        : 'Nothing matched “$_query”. Try a different dish, cuisine or restaurant.',
                    action: FilledButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _cuisine = '';
                          _onlyOpen = false;
                        });
                        _load();
                      },
                      child: const Text('Clear filters'),
                    ),
                  ),
                ),
              )
            else
              ContentWidth(
                child: ResponsiveWrap(
                  minItemWidth: 300,
                  children: [
                    for (final r in visible)
                      RestaurantCard(
                          restaurant: r,
                          onTap: () => context.push('/restaurant/${r.id}')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller,
      required this.onSubmit,
      required this.onClear});

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSubmit(),
      decoration: InputDecoration(
        hintText: 'Search restaurants, cuisines or dishes…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: 'Clear',
          onPressed: onClear,
          icon: const Icon(Icons.close_rounded),
        ),
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
          borderSide: const BorderSide(color: AppColors.forest, width: 1.8),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.forest : AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                  color: selected ? AppColors.forest : AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color:
                          selected ? AppColors.lime : AppColors.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.lime : AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: selected ? AppColors.limeDark : AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.forestDeep),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.forestDeep)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});

  final _SortMode value;
  final ValueChanged<_SortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    String label(_SortMode m) => switch (m) {
          _SortMode.recommended => 'Recommended',
          _SortMode.az => 'Name A–Z',
          _SortMode.za => 'Name Z–A',
          _SortMode.openFirst => 'Open first',
        };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: const Icon(Icons.swap_vert_rounded, size: 18),
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textPrimary),
          items: [
            for (final m in _SortMode.values)
              DropdownMenuItem(value: m, child: Text(label(m))),
          ],
          onChanged: (m) => m == null ? null : onChanged(m),
        ),
      ),
    );
  }
}
