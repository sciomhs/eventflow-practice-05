/// Localized Russian labels for all domain enums, statuses, roles, and audit actions.
abstract final class EfLabels {
  static String eventStatus(String status) => switch (status) {
        'PUBLISHED' => 'Опубликовано',
        'DRAFT' => 'Черновик',
        'CANCELLED' => 'Отменено',
        _ => status,
      };

  static String ticketStatus(String status) => switch (status) {
        'ISSUED' => 'Действителен',
        'USED' => 'Использован',
        'CANCELLED' => 'Отменён',
        _ => status,
      };

  static String role(String role) => switch (role) {
        'participant' => 'Участник',
        'organizer' => 'Организатор',
        'controller' => 'Контролёр',
        _ => role,
      };

  static String auditAction(String action) => switch (action) {
        'TICKET_ISSUE' => 'Выдача билета',
        'TICKET_CANCEL' => 'Отмена билета',
        'CHECKIN' => 'Проверка входа',
        'EVENT_PUBLISH' => 'Публикация события',
        'EVENT_CANCEL' => 'Отмена события',
        _ => action,
      };

  static String auditResult(String result) => switch (result) {
        'ACCEPTED' => 'Вход разрешён',
        'ALREADY_USED' => 'Уже использован',
        'WRONG_EVENT' => 'Другое событие',
        'INVALID' => 'Неверный код',
        'CLOSED' => 'Окно закрыто',
        'SOLD_OUT' => 'Мест нет',
        'CANCELLED' => 'Отменено',
        'ISSUED' => 'Выдан',
        'PUBLISHED' => 'Опубликовано',
        _ => result,
      };
}
