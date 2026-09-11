class CodeWriter {
  CodeWriter({this.indentText = '    '});

  final String indentText;
  final StringBuffer _buffer = StringBuffer();
  int _depth = 0;

  void writeln([String line = '']) {
    if (line.isEmpty) {
      _buffer.write('\n');
      return;
    }
    _buffer
      ..write(indentText * _depth)
      ..write(line)
      ..write('\n');
  }

  void indent(void Function() body) {
    _depth++;
    try {
      body();
    } finally {
      _depth--;
    }
  }

  @override
  String toString() => _buffer.toString();
}
