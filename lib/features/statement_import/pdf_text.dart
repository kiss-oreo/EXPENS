import 'dart:convert';
import 'dart:io';

/// Pulls text out of a PDF without a parser package.
///
/// Handles uncompressed streams and FlateDecode. Text is grouped into lines
/// by position, so a row split across several `Tj` calls still comes back as
/// one line. Unknown encodings and image-only pages yield nothing. Never throws.
class PdfText {
  const PdfText._();

  static String extract(Uint8List bytes) {
    try {
      final items = <_TextItem>[];
      var from = 0;
      while (from < bytes.length) {
        final at = _findStream(bytes, from);
        if (at < 0) break;
        final headStart = at > 800 ? at - 800 : 0;
        final head = latin1.decode(
          bytes.sublist(headStart, at),
          allowInvalid: true,
        );
        final lengthMatch = RegExp(r'/Length\s+(\d+)').allMatches(head);
        final dataStart = _afterStreamKeyword(bytes, at);
        if (lengthMatch.isEmpty || dataStart < 0) {
          from = at + 6;
          continue;
        }
        final length = int.parse(lengthMatch.last.group(1)!);
        if (length < 0 || dataStart + length > bytes.length) {
          from = at + 6;
          continue;
        }
        final raw = bytes.sublist(dataStart, dataStart + length);
        final decoded = head.contains('FlateDecode') ? _inflate(raw) : raw;
        if (decoded.isNotEmpty) {
          items.addAll(_itemsIn(latin1.decode(decoded, allowInvalid: true)));
        }
        from = dataStart + length;
      }
      return _join(items);
    } catch (_) {
      return '';
    }
  }

  static int _findStream(Uint8List bytes, int from) {
    const needle = [115, 116, 114, 101, 97, 109]; // stream
    for (var i = from; i <= bytes.length - needle.length; i++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (!matched) continue;
      if (i > 0 && !_delim(bytes[i - 1])) continue;
      final after = i + needle.length;
      if (after < bytes.length && !_delim(bytes[after])) continue;
      return i;
    }
    return -1;
  }

  static bool _delim(int byte) {
    return byte == 0x20 ||
        byte == 0x09 ||
        byte == 0x0a ||
        byte == 0x0d ||
        byte == 0x3e ||
        byte == 0x5b;
  }

  static int _afterStreamKeyword(Uint8List bytes, int at) {
    var i = at + 6;
    if (i < bytes.length && bytes[i] == 0x0d) i++;
    if (i < bytes.length && bytes[i] == 0x0a) return i + 1;
    if (i < bytes.length && bytes[i - 1] == 0x0d) return i;
    return i;
  }

  static Uint8List _inflate(Uint8List data) {
    try {
      return Uint8List.fromList(zlib.decode(data));
    } catch (_) {
      try {
        return Uint8List.fromList(ZLibCodec(raw: true).decode(data));
      } catch (_) {
        return Uint8List(0);
      }
    }
  }

  static List<_TextItem> _itemsIn(String stream) {
    final tokens = _tokenize(stream);
    final items = <_TextItem>[];
    var x = 0.0;
    var y = 0.0;
    var leading = 14.0;
    final numbers = <double>[];
    var array = 0;

    void emit(String text) {
      if (text.isEmpty) return;
      items.add(_TextItem(x, y, text));
      x += text.length * 5;
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.kind == _Kind.arrayStart) {
        array++;
        continue;
      }
      if (token.kind == _Kind.arrayEnd) {
        if (array > 0) array--;
        continue;
      }
      if (token.kind == _Kind.number) {
        if (array == 0) numbers.add(token.number);
        continue;
      }
      if (token.kind == _Kind.string) {
        final next = i + 1 < tokens.length ? tokens[i + 1] : null;
        if (array > 0 ||
            next?.op == 'Tj' ||
            next?.op == "'" ||
            next?.op == '"') {
          emit(token.text);
        }
        continue;
      }
      final op = token.op;
      if (op == 'Td' || op == 'TD') {
        if (numbers.length >= 2) {
          final tx = numbers[numbers.length - 2];
          final ty = numbers[numbers.length - 1];
          x += tx;
          y += ty;
          if (op == 'TD' && ty != 0) leading = -ty;
        }
      } else if (op == 'Tm' && numbers.length >= 2) {
        x = numbers[numbers.length - 2];
        y = numbers.last;
      } else if (op == 'T*') {
        y -= leading == 0 ? 14 : leading;
      } else if (op == 'TL' && numbers.isNotEmpty) {
        leading = numbers.last;
      } else if (op == "'" || op == '"') {
        y -= leading == 0 ? 14 : leading;
      }
      numbers.clear();
    }
    return items;
  }

  static List<_Token> _tokenize(String stream) {
    final out = <_Token>[];
    var i = 0;
    while (i < stream.length) {
      final c = stream.codeUnitAt(i);
      if (c == 0x25) {
        while (i < stream.length &&
            stream.codeUnitAt(i) != 0x0a &&
            stream.codeUnitAt(i) != 0x0d) {
          i++;
        }
        continue;
      }
      if (c <= 0x20) {
        i++;
        continue;
      }
      if (c == 0x28) {
        final lit = _literal(stream, i);
        out.add(_Token.string(lit.text));
        i = lit.end;
        continue;
      }
      if (c == 0x3c) {
        if (i + 1 < stream.length && stream.codeUnitAt(i + 1) == 0x3c) {
          i += 2;
          continue;
        }
        final hex = _hex(stream, i);
        out.add(_Token.string(hex.text));
        i = hex.end;
        continue;
      }
      if (c == 0x3e) {
        i += i + 1 < stream.length && stream.codeUnitAt(i + 1) == 0x3e ? 2 : 1;
        continue;
      }
      if (c == 0x5b) {
        out.add(const _Token.arrayStart());
        i++;
        continue;
      }
      if (c == 0x5d) {
        out.add(const _Token.arrayEnd());
        i++;
        continue;
      }
      if (c == 0x2f) {
        i++;
        while (i < stream.length && stream.codeUnitAt(i) > 0x20) {
          i++;
        }
        continue;
      }
      final start = i;
      while (i < stream.length && stream.codeUnitAt(i) > 0x20) {
        i++;
      }
      final word = stream.substring(start, i);
      final number = double.tryParse(word);
      if (number != null) {
        out.add(_Token.number(number));
      } else {
        out.add(_Token.op(word));
      }
    }
    return out;
  }

  static _Slice _literal(String s, int i) {
    final buf = StringBuffer();
    i++;
    var depth = 1;
    while (i < s.length && depth > 0) {
      final c = s[i];
      if (c == '\\' && i + 1 < s.length) {
        final n = s[i + 1];
        const named = {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f'};
        if (named.containsKey(n)) {
          buf.write(named[n]);
          i += 2;
          continue;
        }
        if (n == '(' || n == ')' || n == '\\') {
          buf.write(n);
          i += 2;
          continue;
        }
        if (RegExp(r'[0-7]').hasMatch(n)) {
          var j = i + 1;
          var oct = '';
          while (j < s.length && j < i + 4 && RegExp(r'[0-7]').hasMatch(s[j])) {
            oct += s[j];
            j++;
          }
          buf.writeCharCode(int.parse(oct, radix: 8));
          i = j;
          continue;
        }
        buf.write(n);
        i += 2;
        continue;
      }
      if (c == '(') {
        depth++;
        buf.write(c);
        i++;
        continue;
      }
      if (c == ')') {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
        buf.write(c);
        i++;
        continue;
      }
      buf.write(c);
      i++;
    }
    return _Slice(buf.toString(), i);
  }

  static _Slice _hex(String s, int i) {
    final end = s.indexOf('>', i + 1);
    if (end < 0) return _Slice('', s.length);
    final hex = s.substring(i + 1, end).replaceAll(RegExp(r'\s'), '');
    final padded = hex.length.isOdd ? '${hex}0' : hex;
    final bytes = <int>[];
    for (var j = 0; j + 1 < padded.length; j += 2) {
      bytes.add(int.tryParse(padded.substring(j, j + 2), radix: 16) ?? 0);
    }
    return _Slice(_decodeHexBytes(bytes), end + 1);
  }

  static String _decodeHexBytes(List<int> bytes) {
    if (bytes.length >= 2 && bytes.length.isEven) {
      final zeros = bytes.where((b) => b == 0).length;
      if (bytes[0] == 0xfe && bytes[1] == 0xff || zeros >= bytes.length ~/ 3) {
        final start = bytes[0] == 0xfe && bytes[1] == 0xff ? 2 : 0;
        final units = <int>[];
        for (var i = start; i + 1 < bytes.length; i += 2) {
          units.add((bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(units);
      }
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String _join(List<_TextItem> items) {
    if (items.isEmpty) return '';
    final sorted = [...items]..sort((a, b) => b.y.compareTo(a.y));
    final lines = <List<_TextItem>>[];
    for (final item in sorted) {
      if (lines.isEmpty || (lines.last.first.y - item.y).abs() > 2) {
        lines.add([item]);
      } else {
        lines.last.add(item);
      }
    }
    final buf = StringBuffer();
    for (final line in lines) {
      line.sort((a, b) => a.x.compareTo(b.x));
      final parts = <String>[];
      for (var i = 0; i < line.length; i++) {
        if (i > 0 &&
            !line[i - 1].text.endsWith(' ') &&
            !line[i].text.startsWith(' ')) {
          parts.add(' ');
        }
        parts.add(line[i].text);
      }
      final text = parts.join().trim();
      if (text.isNotEmpty) buf.writeln(text);
    }
    return buf.toString();
  }
}

class _TextItem {
  const _TextItem(this.x, this.y, this.text);
  final double x;
  final double y;
  final String text;
}

enum _Kind { string, number, op, arrayStart, arrayEnd }

class _Token {
  const _Token._(this.kind, this.text, this.number, this.op);
  const _Token.arrayStart() : this._(_Kind.arrayStart, '', 0.0, '');
  const _Token.arrayEnd() : this._(_Kind.arrayEnd, '', 0.0, '');
  factory _Token.string(String text) => _Token._(_Kind.string, text, 0, '');
  factory _Token.number(double number) =>
      _Token._(_Kind.number, '', number, '');
  factory _Token.op(String op) => _Token._(_Kind.op, '', 0, op);

  final _Kind kind;
  final String text;
  final double number;
  final String op;
}

class _Slice {
  const _Slice(this.text, this.end);
  final String text;
  final int end;
}
