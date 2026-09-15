/// 占位作者集合（trim + 大小写不敏感）：空串、无、未知、未填写、unknown、
/// anonymous、none、n/a、佚名。
const List<String> placeholderAuthors = <String>[
  '',
  '无',
  '未知',
  '未填写',
  'unknown',
  'anonymous',
  'none',
  'n/a',
  '佚名',
];

/// 作者是否为占位值（trim + 大小写不敏感）。
bool isPlaceholderAuthor(String author) {
  return placeholderAuthors.contains(author.trim().toLowerCase());
}

/// 默认作者非空且 [author] 为占位时返回默认作者（trim 后），否则原样返回。
String resolveDefaultAuthor(String author, String defaultAuthor) {
  final String fallback = defaultAuthor.trim();
  if (fallback.isEmpty || !isPlaceholderAuthor(author)) {
    return author;
  }
  return fallback;
}
