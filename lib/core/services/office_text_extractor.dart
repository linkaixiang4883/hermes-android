import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Bounded, offline text extracted from a modern Office container.
class OfficeTextPreview {
  final String format;
  final String text;
  final bool truncated;

  const OfficeTextPreview({
    required this.format,
    required this.text,
    required this.truncated,
  });
}

/// Extracts selectable text from DOCX/XLSX/PPTX without rendering formatting,
/// images, charts, formulas or external relationships.
///
/// The parser runs in an isolate: a hostile ZIP/XML case must not block the UI.
/// Unsupported/legacy/encrypted files return `null`; callers keep Download and
/// Share available for those.
Future<OfficeTextPreview?> extractOfficeText({
  required Uint8List bytes,
  required String filename,
}) {
  final extension = _extensionOf(filename);
  if (!const {'docx', 'xlsx', 'pptx'}.contains(extension)) {
    return Future.value(null);
  }
  return Isolate.run(() => _extractSync(bytes, extension));
}

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
}

const int _maxArchiveBytes = 16 * 1024 * 1024;
const int _maxEntries = 2000;
const int _maxEntryBytes = 20 * 1024 * 1024;
const int _maxTotalBytes = 50 * 1024 * 1024;
const int _maxTextChars = 200000;

OfficeTextPreview? _extractSync(Uint8List bytes, String extension) {
  if (bytes.length > _maxArchiveBytes) return null;
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  final files = archive.files.where((entry) => entry.isFile).toList();
  if (files.length > _maxEntries) return null;
  var total = 0;
  for (final file in files) {
    if (file.isSymbolicLink || file.size > _maxEntryBytes) return null;
    total += file.size;
    if (total > _maxTotalBytes) return null;
  }

  try {
    final text = switch (extension) {
      'docx' => _docx(files),
      'xlsx' => _xlsx(files),
      'pptx' => _pptx(files),
      _ => null,
    };
    if (text == null) return null;
    final capped = text.length > _maxTextChars
        ? text.substring(0, _maxTextChars)
        : text;
    return OfficeTextPreview(
      format: extension,
      text: capped.trim(),
      truncated: text.length > _maxTextChars,
    );
  } catch (_) {
    return null;
  }
}

String? _docx(List<ArchiveFile> files) {
  final document = _find(files, 'word/document.xml');
  if (document == null) return null;
  final documentBytes = _readEntry(document);
  if (documentBytes == null) return null;
  final xml = XmlDocument.parse(utf8.decode(documentBytes));
  final lines = <String>[];
  for (final paragraph in xml.findAllElements('w:p')) {
    final text = paragraph
        .findAllElements('w:t')
        .map((node) => node.innerText)
        .join();
    if (text.trim().isNotEmpty) lines.add(text.trim());
  }
  return lines.join('\n');
}

String? _xlsx(List<ArchiveFile> files) {
  final workbook = _find(files, 'xl/workbook.xml');
  if (workbook == null) return null;
  final workbookBytes = _readEntry(workbook);
  if (workbookBytes == null) return null;
  final workbookXml = XmlDocument.parse(utf8.decode(workbookBytes));
  final sheetNames = [
    for (final sheet in workbookXml.findAllElements('sheet'))
      sheet.getAttribute('name') ?? 'Sheet',
  ];

  final sharedStrings = <String>[];
  final stringsFile = _find(files, 'xl/sharedStrings.xml');
  if (stringsFile != null) {
    final stringsBytes = _readEntry(stringsFile);
    if (stringsBytes == null) return null;
    final xml = XmlDocument.parse(utf8.decode(stringsBytes));
    for (final item in xml.findAllElements('si')) {
      sharedStrings.add(item.findAllElements('t').map((n) => n.innerText).join());
    }
  }

  final sheetFiles = files
      .where(
        (file) =>
            file.name.startsWith('xl/worksheets/sheet') &&
            file.name.endsWith('.xml'),
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  final buffer = StringBuffer();
  for (var index = 0; index < sheetFiles.length; index++) {
    final name = index < sheetNames.length ? sheetNames[index] : 'Sheet ${index + 1}';
    buffer.writeln('[Sheet: $name]');
    final sheetBytes = _readEntry(sheetFiles[index]);
    if (sheetBytes == null) return null;
    final xml = XmlDocument.parse(utf8.decode(sheetBytes));
    for (final row in xml.findAllElements('row')) {
      final cells = <String>[];
      for (final cell in row.findAllElements('c')) {
        final coordinate = cell.getAttribute('r') ?? '';
        final type = cell.getAttribute('t');
        final valueNode = cell.findElements('v').isEmpty
            ? null
            : cell.findElements('v').first;
        final inline = cell.findAllElements('t').map((n) => n.innerText).join();
        final raw = valueNode?.innerText ?? inline;
        if (raw.isEmpty) continue;
        var value = raw;
        if (type == 's') {
          final sharedIndex = int.tryParse(raw);
          value = sharedIndex != null &&
                  sharedIndex >= 0 &&
                  sharedIndex < sharedStrings.length
              ? sharedStrings[sharedIndex]
              : '';
        }
        if (value.isEmpty) continue;
        cells.add(coordinate.isEmpty ? value : '$coordinate=$value');
      }
      if (cells.isNotEmpty) buffer.writeln(cells.join('\t'));
    }
    buffer.writeln();
  }
  return buffer.toString();
}

String? _pptx(List<ArchiveFile> files) {
  final slides = files
      .where(
        (file) =>
            file.name.startsWith('ppt/slides/slide') &&
            file.name.endsWith('.xml'),
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (slides.isEmpty) return null;
  final buffer = StringBuffer();
  for (var index = 0; index < slides.length; index++) {
    buffer.writeln('[Slide ${index + 1}]');
    final slideBytes = _readEntry(slides[index]);
    if (slideBytes == null) return null;
    final xml = XmlDocument.parse(utf8.decode(slideBytes));
    for (final text in xml.findAllElements('a:t')) {
      final value = text.innerText.trim();
      if (value.isNotEmpty) buffer.writeln(value);
    }
    buffer.writeln();
  }
  return buffer.toString();
}

/// Reads one entry with a hard output cap. `ArchiveFile.size` is only the
/// ZIP header's claim; a hostile document can lie about it, so deflated
/// entries are streamed into a bounded sink instead of `entry.content`.
Uint8List? _readEntry(ArchiveFile file) {
  if (!file.isFile || file.isSymbolicLink) return null;
  final raw = file.rawContent;
  if (raw == null) return null;
  if (raw.length > _maxTotalBytes || file.size > _maxEntryBytes) return null;
  if (file.compression == null || file.compression == CompressionType.none) {
    if (raw.length > _maxEntryBytes) return null;
    return raw.getStream(decompress: false).toUint8List();
  }
  if (file.compression != CompressionType.deflate) return null;
  final output = _BoundedBytesOutput(_maxEntryBytes);
  try {
    ZLibDecoder().decodeStream(
      raw.getStream(decompress: false),
      output,
      raw: true,
    );
  } catch (_) {
    return null;
  }
  if (output.overflow || output.length > _maxEntryBytes) return null;
  return output.getBytes();
}

class _BoundedBytesOutput extends OutputStream {
  _BoundedBytesOutput(this.limit) : super(byteOrder: ByteOrder.littleEndian);

  final int limit;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  bool overflow = false;

  void _ensure(int count) {
    if (count < 0 || _bytes.length + count > limit) {
      overflow = true;
      throw const _ZipLimitExceeded();
    }
  }

  @override
  int get length => _bytes.length;

  @override
  void clear() => _bytes.clear();

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _ensure(1);
    _bytes.addByte(value & 0xff);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _ensure(count);
    _bytes.add(count == bytes.length ? bytes : bytes.sublist(0, count));
  }

  @override
  void writeStream(InputStream stream) {
    final bytes = stream.toUint8List();
    writeBytes(bytes);
  }

  @override
  Uint8List subset(int start, [int? end]) {
    final bytes = _bytes.toBytes();
    return Uint8List.sublistView(bytes, start, end ?? bytes.length);
  }

  @override
  Uint8List getBytes() => _bytes.toBytes();
}

class _ZipLimitExceeded implements Exception {
  const _ZipLimitExceeded();
}

ArchiveFile? _find(List<ArchiveFile> files, String name) {
  for (final file in files) {
    if (file.name == name) return file;
  }
  return null;
}
