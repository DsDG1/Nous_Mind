/// Formats a [DateTime] as `yyyy-MM-dd HH:mm` for display in list rows and
/// editor pickers. Locale-independent, padded to two digits.
String formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
