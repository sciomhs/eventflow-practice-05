import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth_store.dart';
import '../../core/models/models.dart';
import '../../core/sse_client.dart';
import '../../design/tokens.dart';
import '../../design/widgets/ef_widgets.dart';
import 'event_detail_screen.dart';

class ParticipantCatalogScreen extends StatefulWidget {
  final AuthStore auth;
  const ParticipantCatalogScreen({super.key, required this.auth});

  @override
  State<ParticipantCatalogScreen> createState() =>
      _ParticipantCatalogScreenState();
}

class _ParticipantCatalogScreenState extends State<ParticipantCatalogScreen> {
  final _searchCtrl = TextEditingController();
  String _status = 'PUBLISHED';
  String _category = '';
  String _city = '';
  String _datePreset = 'all';
  String _sort = 'starts_at_asc';
  int _page = 1;
  static const int _pageSize = 10;

  bool _loading = true;
  String? _error;
  List<EventItem> _items = [];
  int _total = 0;

  StreamSubscription<SseMessage>? _sseSub;
  StreamSubscription<void>? _reconnSub;

  @override
  void initState() {
    super.initState();
    _load();
    _sseSub = widget.auth.sse.messages.listen((msg) {
      if (msg.event == 'ticket.issued' ||
          msg.event == 'ticket.cancelled' ||
          msg.event == 'event.updated' ||
          msg.event == 'event.cancelled') {
        _load(silent: true);
      }
    });
    _reconnSub =
        widget.auth.sse.onReconnected.listen((_) => _load(silent: true));
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _reconnSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final query = <String, String>{
        'status': _status,
        'sort': _sort,
        'page': '$_page',
        'page_size': '$_pageSize',
      };
      if (_searchCtrl.text.trim().isNotEmpty)
        query['search'] = _searchCtrl.text.trim();
      if (_category.isNotEmpty) query['category'] = _category;
      if (_city.isNotEmpty) query['city'] = _city;
      final now = DateTime.now().toUtc();
      if (_datePreset == 'today') {
        query['date_from'] =
            now.subtract(const Duration(hours: 12)).toIso8601String();
        query['date_to'] = now.add(const Duration(hours: 24)).toIso8601String();
      } else if (_datePreset == 'week') {
        query['date_from'] = now.toIso8601String();
        query['date_to'] = now.add(const Duration(days: 7)).toIso8601String();
      }

      final res = await widget.auth.api.get('/api/v1/events', query: query);
      final list = (res['items'] as List<dynamic>)
          .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _items = list;
          _total = (res['total'] as num).toInt();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1000 ? 2 : 1;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(EfSpacing.lg),
        children: [
          Text('Мероприятия', style: EfTextStyles.display(28)),
          const SizedBox(height: EfSpacing.xs),
          Text(
            'Выберите событие и категорию билета. Остаток мест обновляется в реальном времени.',
            style: EfTextStyles.body(14, color: EfColors.mutedSlate),
          ),
          const SizedBox(height: EfSpacing.lg),
          // 6 filters
          Wrap(
            spacing: EfSpacing.md,
            runSpacing: EfSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: width >= 600 ? 280 : double.infinity,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Поиск по названию или залу',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _page = 1;
                              _load();
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) {
                    _page = 1;
                    _load();
                  },
                ),
              ),
              _FilterDropdown(
                label: 'Статус',
                value: _status,
                items: const {
                  'PUBLISHED': 'Опубликованные',
                  'CANCELLED': 'Отменённые'
                },
                onChanged: (v) {
                  _status = v;
                  _page = 1;
                  _load();
                },
              ),
              _FilterDropdown(
                label: 'Категория',
                value: _category,
                items: const {
                  '': 'Все',
                  'Технологии': 'Технологии',
                  'Дизайн': 'Дизайн',
                  'Хакатон': 'Хакатон'
                },
                onChanged: (v) {
                  _category = v;
                  _page = 1;
                  _load();
                },
              ),
              _FilterDropdown(
                label: 'Город',
                value: _city,
                items: const {
                  '': 'Все города',
                  'Екатеринбург': 'Екатеринбург',
                  'Москва': 'Москва',
                  'Санкт-Петербург': 'Санкт-Петербург'
                },
                onChanged: (v) {
                  _city = v;
                  _page = 1;
                  _load();
                },
              ),
              _FilterDropdown(
                label: 'Дата',
                value: _datePreset,
                items: const {
                  'all': 'Любая дата',
                  'today': 'Ближайшие 24 ч',
                  'week': 'На 7 дней'
                },
                onChanged: (v) {
                  _datePreset = v;
                  _page = 1;
                  _load();
                },
              ),
              _FilterDropdown(
                label: 'Сортировка',
                value: _sort,
                items: const {
                  'starts_at_asc': 'Сначала ближайшие',
                  'starts_at_desc': 'Сначала поздние',
                  'seats_desc': 'Больше мест',
                },
                onChanged: (v) {
                  _sort = v;
                  _page = 1;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: EfSpacing.lg),
          if (_error != null) ...[
            EfErrorBanner(message: _error!, onRetry: _load),
            const SizedBox(height: EfSpacing.lg),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(EfSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            EfEmptyState(
              icon: Icons.event_busy_outlined,
              title: 'События не найдены',
              subtitle:
                  'Попробуйте сбросить фильтры или изменить поисковый запрос.',
              actionLabel: 'Сбросить фильтры',
              onAction: () {
                _searchCtrl.clear();
                _status = 'PUBLISHED';
                _category = '';
                _city = '';
                _datePreset = 'all';
                _page = 1;
                _load();
              },
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                if (cols == 1) {
                  return Column(
                    children: _items
                        .map((ev) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: EfSpacing.md),
                              child: _EventCard(
                                  event: ev, onOpen: () => _openDetail(ev)),
                            ))
                        .toList(),
                  );
                }
                final cardWidth = (constraints.maxWidth - EfSpacing.md) / 2;
                return Wrap(
                  spacing: EfSpacing.md,
                  runSpacing: EfSpacing.md,
                  children: _items
                      .map((ev) => SizedBox(
                            width: cardWidth,
                            child: _EventCard(
                                event: ev, onOpen: () => _openDetail(ev)),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: EfSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Всего: $_total',
                    style: EfTextStyles.body(13, color: EfColors.mutedSlate)),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _page > 1
                          ? () {
                              _page--;
                              _load();
                            }
                          : null,
                      child: const Text('Назад'),
                    ),
                    const SizedBox(width: EfSpacing.sm),
                    Text('Стр. $_page', style: EfTextStyles.mono(13)),
                    const SizedBox(width: EfSpacing.sm),
                    OutlinedButton(
                      onPressed: _page * _pageSize < _total
                          ? () {
                              _page++;
                              _load();
                            }
                          : null,
                      child: const Text('Вперёд'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openDetail(EventItem ev) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(auth: widget.auth, eventId: ev.id),
      ),
    );
    _load(silent: true);
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: EfColors.pureCard,
          borderRadius: BorderRadius.circular(EfRadii.md),
          border: Border.all(color: EfColors.hairlineBorder),
        ),
        child: DropdownButton<String>(
          value: items.containsKey(value) ? value : items.keys.first,
          hint: Text(label),
          items: items.entries
              .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, style: EfTextStyles.body(13))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventItem event;
  final VoidCallback onOpen;

  const _EventCard({required this.event, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM, HH:mm');
    final isCancelled = event.status == 'CANCELLED';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                EfStatusPill(
                  label: event.category,
                  icon: Icons.label_outline,
                  tone: EfTone.neutral,
                ),
                EfStatusPill(
                  label:
                      isCancelled ? 'Отменено' : 'Свободно: ${event.freeSeats}',
                  icon: isCancelled
                      ? Icons.cancel_outlined
                      : Icons.event_seat_outlined,
                  tone: isCancelled
                      ? EfTone.danger
                      : (event.freeSeats > 0
                          ? EfTone.positive
                          : EfTone.warning),
                ),
              ],
            ),
            const SizedBox(height: EfSpacing.md),
            Text(event.title, style: EfTextStyles.display(20)),
            const SizedBox(height: EfSpacing.xs),
            Text(
              '${df.format(event.startsAt.toLocal())} (${event.timezone}) • ${event.city}, ${event.location}',
              style: EfTextStyles.body(13, color: EfColors.mutedSlate),
            ),
            const SizedBox(height: EfSpacing.sm),
            Text(
              event.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: EfTextStyles.body(14),
            ),
            const SizedBox(height: EfSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onOpen,
                child: const Text('Подробнее и регистрация'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
