import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/validators.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class AuthScreen extends StatefulWidget {
  final AuthStore auth;

  const AuthScreen({super.key, required this.auth});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isRegister = false;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      if (_isRegister) {
        await widget.auth
            .register(_nameCtrl.text, _emailCtrl.text, _passCtrl.text);
      } else {
        await widget.auth.login(_emailCtrl.text, _passCtrl.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = e.toString());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _fillDemo(String email) {
    setState(() {
      _isRegister = false;
      _emailCtrl.text = email;
      _passCtrl.text = 'EventFlow2026!';
      _errorText = null;
    });
  }

  Future<void> _openServerDialog() async {
    final ctrl = TextEditingController(text: widget.auth.baseUrl);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Адрес сервера', style: EfTextStyles.display(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Для Android-эмулятора используйте http://10.0.2.2:8000, для локальной сети — IP компьютера.',
              style: EfTextStyles.body(13, color: EfColors.mutedSlate),
            ),
            const SizedBox(height: EfSpacing.md),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'URL сервера'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (saved != null && saved.trim().isNotEmpty) {
      await widget.auth.setBaseUrl(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 820;

    final formCard = Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(EfSpacing.xl),
      decoration: BoxDecoration(
        color: EfColors.pureCard,
        borderRadius: BorderRadius.circular(EfRadii.xl),
        border: Border.all(color: EfColors.hairlineBorder),
        boxShadow: EfShadows.softCard,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _isRegister ? 'Регистрация' : 'Вход в систему',
                    style: EfTextStyles.display(24),
                  ),
                ),
                IconButton(
                  tooltip: 'Адрес сервера',
                  onPressed: _openServerDialog,
                  icon: const Icon(Icons.dns_outlined,
                      color: EfColors.mutedSlate),
                ),
              ],
            ),
            const SizedBox(height: EfSpacing.xs),
            Text(
              'Сервер: ${widget.auth.baseUrl}',
              style: EfTextStyles.mono(11, color: EfColors.mutedSlate),
            ),
            const SizedBox(height: EfSpacing.lg),
            if (_errorText != null) ...[
              EfErrorBanner(message: _errorText!),
              const SizedBox(height: EfSpacing.md),
            ],
            if (_isRegister) ...[
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Имя и фамилия'),
                validator: (v) => EfValidators.requiredText(v, field: 'Имя'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: EfSpacing.md),
            ],
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: EfValidators.email,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: EfSpacing.md),
            TextFormField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: 'Пароль'),
              obscureText: true,
              validator: EfValidators.password,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: EfSpacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: EfColors.pureCard),
                    )
                  : Text(_isRegister ? 'Создать аккаунт участника' : 'Войти'),
            ),
            const SizedBox(height: EfSpacing.md),
            TextButton(
              onPressed: () => setState(() {
                _isRegister = !_isRegister;
                _errorText = null;
              }),
              child: Text(
                _isRegister
                    ? 'Уже есть аккаунт? Войти'
                    : 'Нет аккаунта? Зарегистрироваться',
                style: EfTextStyles.body(14,
                    weight: FontWeight.w600, color: EfColors.emeraldDark),
              ),
            ),
            const Divider(height: EfSpacing.xl, color: EfColors.hairlineBorder),
            Text('Быстрый вход (dev-аккаунты):',
                style: EfTextStyles.body(12, color: EfColors.mutedSlate)),
            const SizedBox(height: EfSpacing.sm),
            Wrap(
              spacing: EfSpacing.sm,
              runSpacing: EfSpacing.sm,
              children: [
                ActionChip(
                    label: const Text('Участник 1'),
                    onPressed: () => _fillDemo('participant1@eventflow.dev')),
                ActionChip(
                    label: const Text('Организатор'),
                    onPressed: () => _fillDemo('organizer@eventflow.dev')),
                ActionChip(
                    label: const Text('Контролёр 1'),
                    onPressed: () => _fillDemo('controller1@eventflow.dev')),
                ActionChip(
                    label: const Text('Контролёр 2'),
                    onPressed: () => _fillDemo('controller2@eventflow.dev')),
              ],
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EfSpacing.lg),
            child: wide
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _BrandIntro()),
                        const SizedBox(width: EfSpacing.xxl),
                        formCard,
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BrandIntro(compact: true),
                      const SizedBox(height: EfSpacing.xl),
                      formCard,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BrandIntro extends StatelessWidget {
  final bool compact;
  const _BrandIntro({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        const EfStatusPill(
          label: 'EVENTFLOW / ПРАКТИКА 05',
          icon: Icons.confirmation_number_outlined,
          tone: EfTone.positive,
        ),
        const SizedBox(height: EfSpacing.lg),
        Text(
          'От регистрации\nдо одного честного входа',
          style: EfTextStyles.display(compact ? 28 : 40),
          textAlign: compact ? TextAlign.center : TextAlign.left,
        ),
        const SizedBox(height: EfSpacing.md),
        Text(
          'Единая платформа для участников, организаторов и контролёров. Серверная транзакционная проверка QR-билетов и синхронизация в реальном времени.',
          style: EfTextStyles.body(15, color: EfColors.mutedSlate),
          textAlign: compact ? TextAlign.center : TextAlign.left,
        ),
      ],
    );
  }
}
