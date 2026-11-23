import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/date_fmt.dart';
import '../../core/models/models.dart';
import '../../core/sse_client.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';

class ControllerScannerScreen extends StatefulWidget {
  final AuthStore auth;
  const ControllerScannerScreen({super.key, required this.auth});

  @override
  State<ControllerScannerScreen> createState() =>
      _ControllerScannerScreenState();
}

class _ControllerScannerScreenState extends State<ControllerScannerScreen> {
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _loadingEvents = true;
  String? _eventsError;
  List<EventItem> _events = [];
  String? _selectedEventId;
  bool _revokedLive = false;

  bool _cameraActive = false;
  bool _inFlight = false;
  String? _pendingRequestId;
  String? _pendingQr;
  CheckInResult? _result;
  String? _fatalError;

  StreamSubscription<SseMessage>? _sseSub;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _sseSub = widget.auth.sse.messages.listen((msg) {
      if (msg.event == 'controller.revoked') {
        final eid = msg.data['event_id']?.toString();
        final cid = msg.data['controller_id']?.toString();
        if (cid == widget.auth.user?.id &&
            (eid == null || eid == _selectedEventId)) {
          if (mounted) {
            setState(() {
              _revokedLive = true;
              _cameraActive = false;
            });
            _loadEvents();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _supportsCamera {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loadingEvents = true;
      _eventsError = null;
    });
    try {
      final res = await widget.auth.api.get('/api/v1/controller/events');
      final list = (res['items'] as List<dynamic>)
          .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _events = list;
          if (_selectedEventId == null ||
              !list.any((e) => e.id == _selectedEventId)) {
            _selectedEventId = list.isNotEmpty ? list.first.id : null;
          }
          if (list.any((e) => e.id == _selectedEventId)) {
            _revokedLive = false;
          }
          _loadingEvents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _eventsError = e.toString();
          _loadingEvents = false;
        });
      }
    }
  }

  Future<void> _submitCheckIn(String rawCode, {bool isRetry = false}) async {
    final code = rawCode.trim();
    if (code.isEmpty || _selectedEventId == null || _inFlight || _revokedLive) {
      return;
    }
    if (!isRetry && _result != null) {
      return; // Require explicit "Следующий посетитель"
    }

    _pendingQr = code;
    _pendingRequestId ??= const Uuid().v4();

    setState(() {
      _inFlight = true;
      _cameraActive = false;
      _fatalError = null;
    });

    try {
      final res =
          await widget.auth.api.post('/api/v1/controller/checkin', body: {
        'event_id': _selectedEventId,
        'qr_token': code,
        'request_id': _pendingRequestId,
      });
      final parsed = CheckInResult.fromJson(res);
      if (mounted) {
        setState(() {
          _result = parsed;
          _inFlight = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _inFlight = false;
          if (e.statusCode == 403) {
            _revokedLive = true;
            _result = CheckInResult(
              status: 'FORBIDDEN',
              idempotentReplay: false,
              message:
                  'Доступ контролёра отозван или не назначен на это событие (403).',
            );
          } else if (e.statusCode == 409) {
            _pendingRequestId = null;
            _result = CheckInResult(
              status: 'CONFLICT',
              idempotentReplay: false,
              message: e.message,
            );
          } else {
            _fatalError = e.message;
            _result = CheckInResult(
              status: 'UNCERTAIN',
              idempotentReplay: false,
              message: 'Ошибка сервера (${e.statusCode}): ${e.message}',
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inFlight = false;
          _fatalError = e.toString();
          _result = const CheckInResult(
            status: 'UNCERTAIN',
            idempotentReplay: false,
            message:
                'Нет связи или истёк таймаут. Допуск ещё не подтверждён. Повторите запрос.',
          );
        });
      }
    }
  }

  void _nextVisitor() {
    setState(() {
      _result = null;
      _fatalError = null;
      _pendingRequestId = null;
      _pendingQr = null;
      _codeCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingEvents) {
      return const Padding(
        padding: EdgeInsets.all(EfSpacing.lg),
        child: Column(children: [EfSkeletonCard(height: 180)]),
      );
    }
    if (_eventsError != null) {
      return Padding(
        padding: const EdgeInsets.all(EfSpacing.lg),
        child: EfErrorBanner(message: _eventsError!, onRetry: _loadEvents),
      );
    }
    if (_events.isEmpty) {
      return EfEmptyState(
        icon: Icons.qr_code_scanner,
        title: _revokedLive
            ? 'Назначение контролёра отозвано'
            : 'Нет назначенных событий',
        subtitle:
            'Попросите организатора назначить ваш аккаунт на мероприятие.',
        actionLabel: 'Обновить список',
        onAction: _loadEvents,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(EfSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Контроль входа', style: EfTextStyles.display(28)),
              const SizedBox(height: EfSpacing.md),
              if (_revokedLive) ...[
                EfErrorBanner(
                  message:
                      'Ваше назначение на это событие отозвано организатором. Новые проверки заблокированы.',
                  onRetry: _loadEvents,
                ),
                const SizedBox(height: EfSpacing.md),
              ],
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _selectedEventId,
                decoration:
                    const InputDecoration(labelText: 'Назначенное мероприятие'),
                items: _events
                    .map((e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            '${e.title} (${e.location})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: _result == null && !_inFlight
                    ? (v) => setState(() {
                          _selectedEventId = v;
                          _revokedLive = false;
                        })
                    : null,
              ),
              const SizedBox(height: EfSpacing.lg),
              if (_result != null)
                _ResultCard(
                  result: _result!,
                  fatalError: _fatalError,
                  onRetrySameRequest:
                      _result!.status == 'UNCERTAIN' && _pendingQr != null
                          ? () => _submitCheckIn(_pendingQr!, isRetry: true)
                          : null,
                  onNext: _nextVisitor,
                )
              else ...[
                if (_supportsCamera) ...[
                  if (_cameraActive)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(EfRadii.lg),
                      child: SizedBox(
                        height: 280,
                        child: MobileScanner(
                          errorBuilder: (context, error) {
                            return Container(
                              color: EfColors.warmStone,
                              padding: const EdgeInsets.all(EfSpacing.lg),
                              child: Center(
                                child: Text(
                                  'Камера недоступна или доступ запрещён (${error.errorCode.name}). Используйте ввод полного кода ниже.',
                                  textAlign: TextAlign.center,
                                  style: EfTextStyles.body(14,
                                      weight: FontWeight.w600),
                                ),
                              ),
                            );
                          },
                          onDetect: (capture) {
                            if (_inFlight || _result != null || _revokedLive) {
                              return;
                            }
                            final raw = capture.barcodes.firstOrNull?.rawValue;
                            if (raw != null && raw.trim().isNotEmpty) {
                              _submitCheckIn(raw);
                            }
                          },
                        ),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _revokedLive
                          ? null
                          : () => setState(() => _cameraActive = true),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Включить камеру для сканирования QR'),
                    ),
                  const SizedBox(height: EfSpacing.lg),
                ],
                TextField(
                  controller: _codeCtrl,
                  focusNode: _codeFocus,
                  enabled: !_revokedLive,
                  decoration: const InputDecoration(
                    labelText: 'Полный код билета (EF1:...)',
                    hintText: 'Вставьте код или отсканируйте USB-сканером',
                  ),
                  onSubmitted: (v) => _submitCheckIn(v),
                ),
                const SizedBox(height: EfSpacing.md),
                FilledButton(
                  onPressed: (_inFlight || _revokedLive)
                      ? null
                      : () => _submitCheckIn(_codeCtrl.text),
                  child: _inFlight
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: EfColors.pureCard),
                        )
                      : const Text('Проверить и зафиксировать вход'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final CheckInResult result;
  final String? fatalError;
  final VoidCallback? onRetrySameRequest;
  final VoidCallback onNext;

  const _ResultCard({
    required this.result,
    this.fatalError,
    this.onRetrySameRequest,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final (String title, IconData icon, EfTone tone) = switch (result.status) {
      'ACCEPTED' => (
          'ВХОД РАЗРЕШЁН',
          Icons.check_circle_rounded,
          EfTone.positive
        ),
      'ALREADY_USED' => (
          'УЖЕ ИСПОЛЬЗОВАН',
          Icons.warning_amber_rounded,
          EfTone.warning
        ),
      'WRONG_EVENT' => (
          'ДРУГОЕ СОБЫТИЕ',
          Icons.swap_horiz_rounded,
          EfTone.danger
        ),
      'INVALID' => ('НЕВЕРНЫЙ КОД', Icons.error_outline_rounded, EfTone.danger),
      'CLOSED' => (
          'ОКНО ДОПУСКА ЗАКРЫТО',
          Icons.schedule_rounded,
          EfTone.warning
        ),
      'SOLD_OUT' => ('МЕСТ НЕТ', Icons.block_rounded, EfTone.warning),
      'CANCELLED' => (
          'БИЛЕТ ИЛИ СОБЫТИЕ ОТМЕНЕНО',
          Icons.cancel_rounded,
          EfTone.danger
        ),
      'FORBIDDEN' => (
          'ДОСТУП ОТОЗВАН (403)',
          Icons.gpp_bad_outlined,
          EfTone.danger
        ),
      'CONFLICT' => (
          'КОНФЛИКТ ЗАПРОСА (409)',
          Icons.warning_rounded,
          EfTone.danger
        ),
      _ => ('РЕЗУЛЬТАТ УТОЧНЯЕТСЯ', Icons.sync_problem_rounded, EfTone.warning),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EfSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: EfStatusPill(label: title, icon: icon, tone: tone),
            ),
            const SizedBox(height: EfSpacing.md),
            if (result.idempotentReplay && result.status == 'ACCEPTED')
              Padding(
                padding: const EdgeInsets.only(bottom: EfSpacing.sm),
                child: Text(
                  'Вход уже зарегистрирован этим запросом (повтор ответа).',
                  style: EfTextStyles.body(13,
                      weight: FontWeight.w600, color: EfColors.emeraldDark),
                ),
              ),
            Text(result.message, style: EfTextStyles.body(15)),
            if (result.ticketCode != null) ...[
              const SizedBox(height: EfSpacing.md),
              Text(
                'Билет: ${result.ticketCode} • ${result.typeName ?? ''}',
                style: EfTextStyles.mono(14),
              ),
            ],
            if (result.participantName != null)
              Text('Участник: ${result.participantName}',
                  style: EfTextStyles.body(14, weight: FontWeight.w600)),
            if (result.usedAt != null)
              Text(
                'Время первого входа (сервер): ${EfDateFmt.dateTimeSeconds(result.usedAt!)}',
                style: EfTextStyles.mono(12, color: EfColors.mutedSlate),
              ),
            if (fatalError != null) ...[
              const SizedBox(height: EfSpacing.sm),
              Text(fatalError!,
                  style: EfTextStyles.body(12, color: EfColors.coral)),
            ],
            const SizedBox(height: EfSpacing.xl),
            if (onRetrySameRequest != null) ...[
              FilledButton(
                onPressed: onRetrySameRequest,
                child: const Text('Повторить с тем же request_id'),
              ),
              const SizedBox(height: EfSpacing.sm),
            ],
            OutlinedButton(
              onPressed: onNext,
              child: const Text('Следующий посетитель'),
            ),
          ],
        ),
      ),
    );
  }
}
