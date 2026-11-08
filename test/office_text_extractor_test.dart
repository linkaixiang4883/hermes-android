import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/office_text_extractor.dart';

Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('extracts DOCX paragraph and table text', () async {
    final bytes = _zip({
      'word/document.xml': '''
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Hello</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
          </w:body>
        </w:document>''',
    });

    final preview = await extractOfficeText(bytes: bytes, filename: 'a.docx');

    expect(preview, isNotNull);
    expect(preview!.text, contains('Hello'));
    expect(preview.text, contains('Cell'));
    expect(preview.format, 'docx');
  });

  test('extracts XLSX sheet names and raw cell values', () async {
    final bytes = _zip({
      'xl/workbook.xml': '''
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheets><sheet name="Budget" sheetId="1"/></sheets>
        </workbook>''',
      'xl/sharedStrings.xml': '''
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>Revenue</t></si>
        </sst>''',
      'xl/worksheets/sheet1.xml': '''
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>42</v></c></row>
          </sheetData>
        </worksheet>''',
    });

    final preview = await extractOfficeText(bytes: bytes, filename: 'a.xlsx');

    expect(preview, isNotNull);
    expect(preview!.text, contains('[Sheet: Budget]'));
    expect(preview.text, contains('A1=Revenue'));
    expect(preview.text, contains('B1=42'));
  });

  test('extracts PPTX slide text in order', () async {
    final bytes = _zip({
      'ppt/slides/slide1.xml': '''
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
               xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <a:t>First slide</a:t>
        </p:sld>''',
    });

    final preview = await extractOfficeText(bytes: bytes, filename: 'a.pptx');

    expect(preview, isNotNull);
    expect(preview!.text, contains('First slide'));
  });

  test('unsupported and corrupt containers return null', () async {
    expect(
      await extractOfficeText(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'a.pdf',
      ),
      isNull,
    );
    expect(
      await extractOfficeText(
        bytes: Uint8List.fromList(utf8.encode('not a zip')),
        filename: 'a.docx',
      ),
      isNull,
    );
  });

  test('rejects an oversized archive before decoding it', () async {
    expect(
      await extractOfficeText(
        bytes: Uint8List(16 * 1024 * 1024 + 1),
        filename: 'large.docx',
      ),
      isNull,
    );
  });
}
