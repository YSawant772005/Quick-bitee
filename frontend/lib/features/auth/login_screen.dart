import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../state/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: _email.text.trim(), password: _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _useDemo(String email, String password) {
    setState(() {
      _email.text = email;
      _password.text = password;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showBrandPanel = width >= 900;

    final form = _LoginForm(
      formKey: _formKey,
      email: _email,
      password: _password,
      obscure: _obscure,
      submitting: _submitting,
      error: _error,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onSubmit: _submit,
      onUseDemo: _useDemo,
      compact: !showBrandPanel,
    );

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: showBrandPanel
          ? Row(
              children: [
                const Expanded(flex: 11, child: _BrandPanel()),
                Expanded(
                  flex: 10,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: form,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: form,
                  ),
                ),
              ),
            ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.forestSoft, AppColors.forestDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: AppColors.lime.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -70,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                color: AppColors.lime.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandLogo(size: 40, onDark: true),
                const Spacer(),
                const Icon(Icons.dinner_dining_rounded, color: AppColors.lime, size: 56),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Great food,\ndelivered fast.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, height: 1.08),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SizedBox(
                  width: 420,
                  child: Text(
                    'Browse real restaurant menus, track every order stage live, and keep a full history of everything you have ordered.',
                    style: TextStyle(color: AppColors.onForestMuted, fontSize: 15, height: 1.55),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    _FeatureChip(icon: Icons.explore_rounded, label: 'Real menus'),
                    _FeatureChip(icon: Icons.local_shipping_outlined, label: 'Live tracking'),
                    _FeatureChip(icon: Icons.receipt_long_outlined, label: 'Order history'),
                  ],
                ),
                const Spacer(),
                const Text('QuickBitee · demo platform',
                    style: TextStyle(color: AppColors.onForestMuted, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.lime),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.email,
    required this.password,
    required this.obscure,
    required this.submitting,
    required this.error,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onUseDemo,
    required this.compact,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool obscure;
  final bool submitting;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final void Function(String email, String password) onUseDemo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            const BrandLogo(size: 44),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Sign in to order your favourites', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'Email address',
                  child: TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  label: 'Password',
                  child: TextFormField(
                    controller: password,
                    obscureText: obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: onToggleObscure,
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    onFieldSubmitted: (_) => onSubmit(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.errorSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login_rounded, size: 19),
                  label: Text(submitting ? 'Signing in…' : 'Sign in'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            color: AppColors.limeSoft,
            border: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.key_outlined, size: 18, color: AppColors.forest),
                    const SizedBox(width: 8),
                    Text('Demo accounts', style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Tap an account to fill the form.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.md),
                _DemoAccount(
                  role: 'Customer',
                  email: 'customer@quickbite.dev',
                  password: 'Customer#123',
                  onTap: () => onUseDemo('customer@quickbite.dev', 'Customer#123'),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DemoAccount(
                  role: 'Admin',
                  email: 'admin@quickbite.dev',
                  password: 'Admin#123',
                  onTap: () => onUseDemo('admin@quickbite.dev', 'Admin#123'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoAccount extends StatelessWidget {
  const _DemoAccount({
    required this.role,
    required this.email,
    required this.password,
    required this.onTap,
  });

  final String role;
  final String email;
  final String password;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          child: Row(
            children: [
              Pill(label: role, color: AppColors.forest, dense: true),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(email, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                    Text(password, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.north_east_rounded, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
