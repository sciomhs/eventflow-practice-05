import 'package:flutter/material.dart';
import '../tokens.dart';

enum EfTone { positive, warning, danger, neutral }

class EfStatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final EfTone tone;

  const EfStatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tone) {
      EfTone.positive => (EfColors.emeraldTint, EfColors.emeraldDark),
      EfTone.warning => (EfColors.amberTint, EfColors.amber),
      EfTone.danger => (EfColors.coralTint, EfColors.coral),
      EfTone.neutral => (EfColors.slateTint, EfColors.mutedSlate),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(EfRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: EfTextStyles.body(12, weight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

class EfPerforatedTicketCard extends StatelessWidget {
  final Widget top;
  final Widget bottom;

  const EfPerforatedTicketCard({
    super.key,
    required this.top,
    required this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EfColors.pureCard,
        borderRadius: BorderRadius.circular(EfRadii.xl),
        border: Border.all(color: EfColors.hairlineBorder),
        boxShadow: EfShadows.softCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(EfSpacing.xl),
            child: top,
          ),
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: EfColors.warmPaper,
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(12)),
                    border: Border(
                      top: BorderSide(color: EfColors.hairlineBorder),
                      bottom: BorderSide(color: EfColors.hairlineBorder),
                      right: BorderSide(color: EfColors.hairlineBorder),
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final count = (constraints.maxWidth / 10).floor();
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          count,
                          (_) => Container(
                            width: 5,
                            height: 1.5,
                            color: EfColors.hairlineBorder,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: 12,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: EfColors.warmPaper,
                    borderRadius:
                        BorderRadius.horizontal(left: Radius.circular(12)),
                    border: Border(
                      top: BorderSide(color: EfColors.hairlineBorder),
                      bottom: BorderSide(color: EfColors.hairlineBorder),
                      left: BorderSide(color: EfColors.hairlineBorder),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(EfSpacing.xl),
            child: bottom,
          ),
        ],
      ),
    );
  }
}

class EfEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EfEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(EfSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: EfColors.warmStone,
                  borderRadius: BorderRadius.circular(EfRadii.lg),
                ),
                child: Icon(icon, size: 28, color: EfColors.mutedSlate),
              ),
              const SizedBox(height: EfSpacing.lg),
              Text(title,
                  style: EfTextStyles.display(20), textAlign: TextAlign.center),
              const SizedBox(height: EfSpacing.sm),
              Text(
                subtitle,
                style: EfTextStyles.body(14, color: EfColors.mutedSlate),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: EfSpacing.lg),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EfErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const EfErrorBanner({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EfSpacing.md),
      decoration: BoxDecoration(
        color: EfColors.coralTint,
        borderRadius: BorderRadius.circular(EfRadii.md),
        border: Border.all(color: EfColors.coral.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: EfColors.coral, size: 20),
          const SizedBox(width: EfSpacing.md),
          Expanded(
            child: Text(
              message,
              style: EfTextStyles.body(13,
                  weight: FontWeight.w500, color: EfColors.deepInk),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Повторить',
                  style: EfTextStyles.body(13,
                      weight: FontWeight.w700, color: EfColors.coral)),
            ),
        ],
      ),
    );
  }
}

class EfConnectionBanner extends StatelessWidget {
  final bool connected;
  final bool reconnecting;

  const EfConnectionBanner({
    super.key,
    required this.connected,
    required this.reconnecting,
  });

  @override
  Widget build(BuildContext context) {
    if (connected) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: reconnecting ? EfColors.amberTint : EfColors.coralTint,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            reconnecting ? Icons.sync : Icons.wifi_off,
            size: 16,
            color: reconnecting ? EfColors.amber : EfColors.coral,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reconnecting
                  ? 'Переподключение к серверу (SSE)... Показаны сохранённые данные.'
                  : 'Нет связи с сервером. Регистрация, отмена и вход недоступны без подтверждения сервера.',
              style: EfTextStyles.body(12, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
