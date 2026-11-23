import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/validators.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class EventEditorScreen extends StatefulWidget {
  final AuthStore auth;
  const EventEditorScreen({super.key, required this.auth});

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Екатеринбург');
  final _locCtrl = TextEditingController();
  final _stdCapCtrl = TextEditingController(text: '40');
  final _vipCapCtrl = TextEditingController(text: '10');
  String _category = 'Технологии';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _cityCtrl.dispose();
    _locCtrl.dispose();
    _stdCapCtrl.dispose();
    _vipCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final stdCap = int.parse(_stdCapCtrl.text.trim());
    final vipCap = int.parse(_vipCapCtrl.text.trim());
    final totalCap = stdCap + vipCap;

    final now = DateTime.now().toUtc();
    final startsAt = now.add(const Duration(hours: 2));
    final endsAt = now.add(const Duration(hours: 6));
    final regCloses = now.add(const Duration(hours: 1, minutes: 45));
    final admOpens = now.subtract(const Duration(minutes: 15));
    final admCloses = now.add(const Duration(hours: 5));

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.auth.api.post('/api/v1/organizer/events', body: {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
        'city': _cityCtrl.text.trim(),
        'location': _locCtrl.text.trim(),
        'starts_at': startsAt.toIso8601String(),
        'ends_at': endsAt.toIso8601String(),
        'timezone': 'Asia/Yekaterinburg',
        'registration_closes_at': regCloses.toIso8601String(),
        'admission_opens_at': admOpens.toIso8601String(),
        'admission_closes_at': admCloses.toIso8601String(),
        'capacity': totalCap,
        'ticket_types': [
          {'name': 'Стандарт', 'capacity': stdCap},
          {'name': 'VIP', 'capacity': vipCap},
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новое мероприятие')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(EfSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    EfErrorBanner(message: _error!),
                    const SizedBox(height: EfSpacing.md),
                  ],
                  TextFormField(
                    controller: _titleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Название события'),
                    validator: (v) =>
                        EfValidators.requiredText(v, field: 'Название'),
                  ),
                  const SizedBox(height: EfSpacing.md),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Описание'),
                    maxLines: 3,
                    validator: (v) =>
                        EfValidators.requiredText(v, field: 'Описание'),
                  ),
                  const SizedBox(height: EfSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Категория'),
                    items: const ['Технологии', 'Дизайн', 'Хакатон']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _category = v ?? 'Технологии'),
                  ),
                  const SizedBox(height: EfSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cityCtrl,
                          decoration: const InputDecoration(labelText: 'Город'),
                          validator: (v) =>
                              EfValidators.requiredText(v, field: 'Город'),
                        ),
                      ),
                      const SizedBox(width: EfSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _locCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Площадка / зал'),
                          validator: (v) =>
                              EfValidators.requiredText(v, field: 'Площадка'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EfSpacing.lg),
                  Text('Категории билетов (минимум 2)',
                      style: EfTextStyles.display(18)),
                  const SizedBox(height: EfSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stdCapCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Лимит «Стандарт»'),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              EfValidators.positiveInt(v, field: 'Лимит'),
                        ),
                      ),
                      const SizedBox(width: EfSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _vipCapCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Лимит «VIP»'),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              EfValidators.positiveInt(v, field: 'Лимит'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EfSpacing.xl),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: EfColors.pureCard),
                          )
                        : const Text('Создать черновик'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
