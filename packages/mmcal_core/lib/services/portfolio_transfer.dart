import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'portfolio_codec.dart';
import 'portfolio_store.dart';

/// Platform IO for exporting and importing the portfolio file. All data
/// shaping lives in [PortfolioCodec] so this layer stays thin and untested
/// (it only touches the OS).
class PortfolioTransfer {
  PortfolioTransfer._();

  /// Writes [contents] to a temp file and hands it to the system share sheet -
  /// the reliable cross-platform way to get a file onto the user's phone
  /// (Files / Drive / email) without requesting storage permissions.
  static Future<void> shareFile(
    String contents, {
    required String fileName,
    required String mimeType,
    required String subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(contents);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: fileName)],
        subject: subject,
      ),
    );
  }

  /// Versioned JSON export - re-importable.
  static Future<void> exportJson(List<PortfolioTxn> txns) => shareFile(
        PortfolioCodec.encodeJson(txns),
        fileName: PortfolioCodec.fileName('json'),
        mimeType: 'application/json',
        subject: 'MMCal portfolio export',
      );

  /// CSV export for spreadsheet viewing - not re-importable.
  static Future<void> exportCsv(List<PortfolioTxn> txns) => shareFile(
        PortfolioCodec.encodeCsv(txns),
        fileName: PortfolioCodec.fileName('csv'),
        mimeType: 'text/csv',
        subject: 'MMCal portfolio export (CSV)',
      );

  /// Only `.json` files are offered to the picker.
  static const XTypeGroup _jsonType = XTypeGroup(
    label: 'MMCal portfolio',
    extensions: ['json'],
    mimeTypes: ['application/json'],
  );

  /// Lets the user pick a previously exported `.json`. Returns the file's
  /// text, or null when they cancelled.
  static Future<String?> pickJson() async {
    final file = await openFile(acceptedTypeGroups: const [_jsonType]);
    if (file == null) return null;
    return file.readAsString();
  }
}
