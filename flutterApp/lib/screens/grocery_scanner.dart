// lib/screens/grocery_scanner.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Image normalization
import 'package:image/image.dart' as img;

import 'package:carbon_pawprint/api/pawprint_api.dart'; // includes ReceiptMapRow
import '../api/base_url.dart';

/// ===== TOP-LEVEL: Editable items model =====
class EditableReceiptItem {
  String name;
  double quantity;
  String? unit;
  Map<String, dynamic> original; // keep original parsed line to rebuild

  EditableReceiptItem({
    required this.name,
    required this.quantity,
    required this.original,
    this.unit,
  });
}

class GroceryScannerScreen extends StatefulWidget {
  const GroceryScannerScreen({super.key});

  @override
  State<GroceryScannerScreen> createState() => _GroceryScannerScreenState();
}

class _GroceryScannerScreenState extends State<GroceryScannerScreen> {
  String? _pickedFile;
  bool _loading = false;
  String? _error;
  List<ReceiptMapRow> _rows = const [];
  double _totalKg = 0.0; // total across mapped items

  late final PawprintApi api;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    api = PawprintApi(pickBaseUrl());
  }

  // ================= Image Normalization =================
  Future<Uint8List> _normalizeImageBytes(Uint8List input) async {
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return input;

      const maxDim = 1600;
      img.Image processed = decoded;
      if (decoded.width > maxDim || decoded.height > maxDim) {
        processed = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDim : null,
          height: decoded.height > decoded.width ? maxDim : null,
          interpolation: img.Interpolation.cubic,
        );
      }

      // force jpeg
      if (processed.numChannels != 3) {
        processed = img.copyResize(
          processed,
          width: processed.width,
          height: processed.height,
        );
      }
      final jpeg = img.encodeJpg(processed, quality: 85);
      return Uint8List.fromList(jpeg);
    } catch (_) {
      return input;
    }
  }

  String _prettyJson(dynamic obj) =>
      const JsonEncoder.withIndent('  ').convert(obj);

  void _printLong(String label, String text) {
    const chunk = 800;
    // ignore: avoid_print
    print('[$label]');
    for (var i = 0; i < text.length; i += chunk) {
      // ignore: avoid_print
      print(text.substring(i, (i + chunk > text.length) ? text.length : i + chunk));
    }
  }

  Future<int?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get('userId');
    int? userid;
    if (raw is int) {
      userid = raw;
    } else if (raw is String) {
      userid = int.tryParse(raw);
      if (userid != null) {
        await prefs.setInt('userId', userid); // migrate to int
      }
    }
    return userid;
  }

  /// Extract a flat list of items from the parser JSON (works for your sample).
  List<EditableReceiptItem> _extractItems(dynamic receiptJson) {
    // Case A: top-level LIST (your parser shape)
    if (receiptJson is List) {
      return receiptJson.whereType<Map>().map<EditableReceiptItem>((m) {
        final name =
        (m['name'] ?? m['description'] ?? m['product'] ?? 'Item').toString();

        final dynamic q = m['qty'] ?? m['quantity'] ?? m['count'] ?? 1;
        double qty;
        if (q is num) {
          qty = q.toDouble();
        } else if (q is String) {
          qty = double.tryParse(q.replaceAll(',', '.')) ?? 1.0;
        } else {
          qty = 1.0;
        }

        final String? unit =
        (m['unit'] ?? m['uom'] ?? m['measure'] ?? m['size_unit'])?.toString();

        return EditableReceiptItem(
          name: name,
          quantity: qty.clamp(0, double.infinity),
          unit: unit,
          original: Map<String, dynamic>.from(m),
        );
      }).toList();
    }

    // Case B: object that contains a list under common keys
    if (receiptJson is Map) {
      final candidates = [
        'items',
        'line_items',
        'lineItems',
        'products',
        'entries',
        'lines',
        'purchases'
      ];
      for (final k in candidates) {
        final v = receiptJson[k];
        if (v is List && v.isNotEmpty && v.first is Map) {
          return _extractItems(v); // reuse the list branch
        }
      }
    }

    return <EditableReceiptItem>[];
  }

  /// Apply user-edited quantities back into the original parser JSON.
  dynamic _applyEditsToReceipt(
      dynamic receiptJson, List<EditableReceiptItem> edited) {
    // A) Top-level LIST (your parser shape)
    if (receiptJson is List) {
      final List<Map<String, dynamic>> rebuilt = [];
      for (final e in edited) {
        final line = Map<String, dynamic>.from(e.original);
        // Update any quantity-like field present
        for (final key in ['qty', 'quantity', 'count', 'amount', 'units']) {
          if (line.containsKey(key)) {
            line[key] = e.quantity;
          }
        }
        // Ensure at least one canonical quantity field exists
        line['qty'] = e.quantity;
        rebuilt.add(line);
      }
      return rebuilt;
    }

    // B) Object containing the list under one of these keys
    if (receiptJson is Map) {
      final listKey = [
        'items',
        'line_items',
        'lineItems',
        'products',
        'entries',
        'lines',
        'purchases'
      ].firstWhere((k) => receiptJson[k] is List, orElse: () => 'items');

      final List<Map<String, dynamic>> rebuilt = [];
      for (final e in edited) {
        final line = Map<String, dynamic>.from(e.original);
        for (final key in ['qty', 'quantity', 'count', 'amount', 'units']) {
          if (line.containsKey(key)) line[key] = e.quantity;
        }
        if (!line.containsKey('qty')) line['qty'] = e.quantity;
        rebuilt.add(line);
      }

      final out = Map<String, dynamic>.from(receiptJson);
      out[listKey] = rebuilt;
      return out;
    }

    // Unknown structure: return original
    return receiptJson;
  }

  /// ===== Parse → EDIT → Map → Update UI + Dashboard bump =====
  Future<void> _processReceiptBytes({
    required Uint8List bytes,
    required String displayName,
    required int userid,
  }) async {
    try {
      setState(() {
        _pickedFile = displayName;
        _loading = true;
        _error = null;
        _rows = const [];
        _totalKg = 0.0;
      });

      // 1) Parse
      final receiptJson = await api.parseReceiptFromBytes(bytes);
      _printLong('receipt_parser result', _prettyJson(receiptJson));

      // 2) EDIT quantities before mapping
      final List<EditableReceiptItem> initialItems = _extractItems(receiptJson);

      final List<EditableReceiptItem>? edited =
      await Navigator.of(context).push<List<EditableReceiptItem>>(
        MaterialPageRoute(
          builder: (_) => EditReceiptItemsPage(
            filename: displayName,
            items: initialItems,
            imageBytesPreview: bytes,
          ),
          fullscreenDialog: true,
        ),
      );

      if (!mounted || edited == null) {
        setState(() => _loading = false);
        return;
      }

      // 3) Rebuild JSON with edited quantities
      final editedReceiptJson = _applyEditsToReceipt(receiptJson, edited);

      // 4) Map for THIS user
      final mappedRows = await api.mapReceiptForUser(userid, editedReceiptJson);
      if (!mounted) return;

      // 5) Update UI totals
      final totalFromReceipt = mappedRows.fold<double>(
        0.0,
            (sum, r) => sum + (r.totalEmissions ?? 0.0),
      );

      setState(() {
        _rows = mappedRows;
        _totalKg = totalFromReceipt;
      });

      // 6) Persist a "pending" bump so Dashboard can show it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('pending_receipt_emissions_$userid', totalFromReceipt);
      await prefs.setString(
          'pending_receipt_desc', 'Grocery receipt • $displayName');
      await prefs.setString(
          'pending_receipt_ts', DateTime.now().toIso8601String());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Added ${totalFromReceipt.toStringAsFixed(2)} kg to Dashboard')),
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Server timed out. Try again.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server timed out. Try again.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Confirmation flow ----------
  Future<void> _showConfirmPage(
      Uint8List bytes,
      String displayName, {
        required bool fromCamera,
      }) async {
    final action = await Navigator.of(context).push<_ConfirmAction>(
      MaterialPageRoute(
        builder: (_) => ConfirmReceiptPage(
          imageBytes: bytes,
          filename: displayName,
        ),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || action == null) return;

    if (action == _ConfirmAction.retry) {
      if (fromCamera) {
        await _takePhoto();
      } else {
        await _pickFromFiles();
      }
      return;
    }

    if (action == _ConfirmAction.confirm) {
      final userid = await _getCurrentUserId();
      if (userid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active user. Please log in again.')),
        );
        return;
      }
      await _processReceiptBytes(
        bytes: bytes,
        displayName: displayName,
        userid: userid,
      );
    }
  }

  // --------- Pick from files ----------
  Future<void> _pickFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic', 'heif'],
      withData: true,
    );
    if (!mounted) return;

    if (result == null || result.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file selected')),
      );
      return;
    }

    final file = result.files.single;
    final name = file.name;
    final Uint8List raw = file.bytes ?? await File(file.path!).readAsBytes();

    final Uint8List bytes = await _normalizeImageBytes(raw);
    await _showConfirmPage(bytes, name, fromCamera: false);
  }

  // --------- Take a live photo ----------
  Future<void> _takePhoto() async {
    final XFile? shot = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 2000,
      maxHeight: 2000,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (!mounted) return;

    if (shot == null) return;

    final bytesRaw = await shot.readAsBytes();
    final bytes = await _normalizeImageBytes(bytesRaw);
    final displayName = shot.name.isNotEmpty ? shot.name : 'camera.jpg';
    await _showConfirmPage(bytes, displayName, fromCamera: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Grocery Receipt Scanner')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 140,
                child: Image.asset(
                  'assets/scan.gif',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.document_scanner, size: 64),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Upload a receipt or take a photo to scan",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),

              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _pickFromFiles,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _loading
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        _loading ? 'Processing…' : 'Choose from Files',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _takePhoto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text(
                        'Take Photo',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (_pickedFile != null)
                Text(
                  "Selected: $_pickedFile",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],

              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ReceiptSummaryCard(
                  totalKg: _totalKg,
                  itemCount: _rows.length,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _receiptCard(_rows[i], theme),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmtKg(num? n) => n == null ? '—' : '${n.toStringAsFixed(2)} kg';

  String _impactLabel(ReceiptMapRow r) {
    final fromBackend = r.impact?.trim();
    if (fromBackend != null && fromBackend.isNotEmpty) return fromBackend;

    final t = r.totalEmissions ?? 0;
    if (t >= 5) return 'High';
    if (t >= 1) return 'Medium';
    if (t > 0) return 'Low';
    return 'Unknown';
  }

  Color _impactColor(String impact, ThemeData theme) {
    switch (impact.toLowerCase()) {
      case 'high':
        return Colors.red.shade500;
      case 'medium':
        return Colors.amber.shade700;
      case 'low':
        return Colors.green.shade600;
      default:
        return theme.colorScheme.secondary;
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _kvChip(String k, String v, {Color? color}) {
    return _chip('$k: $v', color ?? Colors.blueGrey);
  }

  Widget _receiptCard(ReceiptMapRow r, ThemeData theme) {
    final name = r.item ?? r.matchedName ?? 'Item';
    final qty =
    (r.displayQty == null || r.displayQty!.isEmpty) ? '—' : r.displayQty!;
    final impact = _impactLabel(r);
    final impactColor = _impactColor(impact, theme);

    return Card(
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Title + chips
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _kvChip('Qty', qty),
                        _chip('Impact: $impact', impactColor),
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing total emissions label
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r.totalEmissions == null
                        ? '—'
                        : r.totalEmissions!.toStringAsFixed(2),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Total CO₂e',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===== Expandable summary card ===== */
class _ReceiptSummaryCard extends StatefulWidget {
  final double totalKg;
  final int itemCount;
  final Widget child; // the expanded content (per-item list)

  const _ReceiptSummaryCard({
    required this.totalKg,
    required this.itemCount,
    required this.child,
  });

  @override
  State<_ReceiptSummaryCard> createState() => _ReceiptSummaryCardState();
}

class _ReceiptSummaryCardState extends State<_ReceiptSummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF3C4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long,
                        size: 18, color: Color(0xFFFFC107)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total CO₂e',
                          style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.totalKg.toStringAsFixed(2)} kg • ${widget.itemCount} item${widget.itemCount == 1 ? '' : 's'}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _expanded ? 0.5 : 0.0,
                    child: const Icon(Icons.expand_more, size: 22),
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) const Divider(height: 1),

          AnimatedCrossFade(
            crossFadeState:
            _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: widget.child,
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/* ===== Confirmation screen ===== */

enum _ConfirmAction { confirm, retry }

class ConfirmReceiptPage extends StatelessWidget {
  final Uint8List imageBytes;
  final String filename;

  const ConfirmReceiptPage({
    super.key,
    required this.imageBytes,
    required this.filename,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Image'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  const Icon(Icons.insert_photo_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black12,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Center(
                        child: Image.memory(
                          imageBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_ConfirmAction.retry),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFFFC107)),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_ConfirmAction.confirm),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===== NEW: Edit Receipt Items Page ===== */

class EditReceiptItemsPage extends StatefulWidget {
  final String filename;
  final List<EditableReceiptItem> items;
  final Uint8List? imageBytesPreview;

  const EditReceiptItemsPage({
    super.key,
    required this.filename,
    required this.items,
    this.imageBytesPreview,
  });

  @override
  State<EditReceiptItemsPage> createState() => _EditReceiptItemsPageState();
}

class _EditReceiptItemsPageState extends State<EditReceiptItemsPage> {
  late List<EditableReceiptItem> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.items
        .map((e) => EditableReceiptItem(
      name: e.name,
      quantity: e.quantity,
      unit: e.unit,
      original: e.original,
    ))
        .toList();
  }

  void _inc(int i) {
    setState(
            () => _items[i].quantity = (_items[i].quantity + 1).clamp(0, 999999));
  }

  void _dec(int i) {
    setState(
            () => _items[i].quantity = (_items[i].quantity - 1).clamp(0, 999999));
  }

  void _onQtyChanged(int i, String v) {
    final parsed = double.tryParse(v.replaceAll(',', '.'));
    if (parsed == null) return;
    setState(() => _items[i].quantity = parsed.clamp(0, 999999));
  }

  void _remove(int i) {
    setState(() => _items.removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Items'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(_items),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save & Continue'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Optional tiny header with filename + preview
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                if (widget.imageBytesPreview != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(widget.imageBytesPreview!,
                        width: 48, height: 48, fit: BoxFit.cover),
                  )
                else
                  const Icon(Icons.receipt_long, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _items.isEmpty
                ? const Center(
              child: Text('No items detected. Go back and retry.'),
            )
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final it = _items[i];
                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding:
                    const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      children: [
                        // Name + unit
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                it.unit == null || it.unit!.isEmpty
                                    ? '—'
                                    : it.unit!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Quantity controls
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _dec(i),
                              icon: const Icon(
                                  Icons.remove_circle_outline),
                            ),
                            SizedBox(
                              width: 72,
                              child: TextFormField(
                                initialValue:
                                it.quantity.toStringAsFixed(
                                  it.quantity ==
                                      it.quantity
                                          .roundToDouble()
                                      ? 0
                                      : 2,
                                ),
                                textAlign: TextAlign.center,
                                keyboardType:
                                const TextInputType
                                    .numberWithOptions(
                                  signed: false,
                                  decimal: true,
                                ),
                                decoration:
                                const InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                  EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 8),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (v) =>
                                    _onQtyChanged(i, v),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _inc(i),
                              icon: const Icon(
                                  Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),

                        // Remove
                        IconButton(
                          onPressed: () => _remove(i),
                          tooltip: 'Remove',
                          icon:
                          const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
