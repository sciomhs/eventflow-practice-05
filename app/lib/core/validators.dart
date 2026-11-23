abstract final class EfValidators {
  static String? requiredText(String? v, {String field = 'Поле'}) {
    if (v == null || v.trim().isEmpty)
      return '$field обязательно для заполнения';
    return null;
  }

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Введите email';
    if (!v.contains('@') || !v.contains('.'))
      return 'Некорректный формат email';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Введите пароль';
    if (v.length < 6) return 'Минимум 6 символов';
    return null;
  }

  static String? positiveInt(String? v, {String field = 'Значение'}) {
    if (v == null || v.trim().isEmpty) return 'Укажите $field';
    final n = int.tryParse(v.trim());
    if (n == null || n <= 0) return '$field должно быть больше 0';
    return null;
  }
}
