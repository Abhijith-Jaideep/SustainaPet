// lib/screens/grocery_scanner.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carbon_pawprint/api/pawprint_api.dart'; // includes ReceiptMapRow
import '../api/base_url.dart';

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

      // 2) Map for THIS user
      final mappedRows = await api.mapReceiptForUser(
        userid,
        receiptJson,
      );
      if (!mounted) return;

      // Compute total across items and show in UI
      final totalFromReceipt = mappedRows.fold<double>(
        0.0, (sum, r) => sum + (r.totalEmissions ?? 0.0),
      );
      setState(() {
        _rows = mappedRows;
        _totalKg = totalFromReceipt;
      });

      // 3) Write a per-user "pending bump" for dashboard
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('pending_receipt_emissions_$userid', totalFromReceipt);
      await prefs.setString('pending_receipt_desc', 'Grocery receipt • $displayName');
      await prefs.setString('pending_receipt_ts', DateTime.now().toIso8601String());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${totalFromReceipt.toStringAsFixed(2)} kg to Dashboard')),
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
      // User wants to try again with the same source
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

  // --------- Pick from files (existing flow) ----------
  Future<void> _pickFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
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
    final Uint8List bytes = file.bytes ?? await File(file.path!).readAsBytes();

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

    if (shot == null) {
      // user canceled
      return;
    }

    final bytes = await shot.readAsBytes();
    final displayName = shot.name.isNotEmpty ? shot.name : 'camera.jpg';

    await _showConfirmPage(bytes, displayName, fromCamera: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Grocery Receipt Scanner')),
      body: SafeArea(
        top: false, // ✅ don't add extra top inset (AppBar already accounts for status bar)
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), // tighter padding, anchored to top
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Smaller header art
              SizedBox(
                height: 140, // was 200
                child: Image.asset(
                  'assets/scan.gif',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.document_scanner, size: 64), // was 80
                ),
              ),
              const SizedBox(height: 8), // was 24
              const Text(
                "Upload a receipt or take a photo to scan",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12), // was 32

              // Buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48, // was 50
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
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(
                        _loading ? 'Processing…' : 'Choose from Files',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10), // was 12
                ],
              ),

              const SizedBox(height: 12), // was 20

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
                const SizedBox(height: 12), // was 16
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],

              // ===== SUMMARY CARD (tap to expand and see items) =====
              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 16), // was 24
                _ReceiptSummaryCard(
                  totalKg: _totalKg,
                  itemCount: _rows.length,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10), // was 12
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

  // --- UI helpers for mapped rows ---
  String _fmtKg(num? n) => n == null ? '—' : '${n.toStringAsFixed(2)} kg';

  // Prefer backend "impact"; otherwise derive from totalEmissions
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
    final qty = (r.displayQty == null || r.displayQty!.isEmpty) ? '—' : r.displayQty!;
    final impact = _impactLabel(r);
    final impactColor = _impactColor(impact, theme);

    return Card(
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () {}, // future: expand / details
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

              // Trailing total emissions label (clean text, no circle)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r.totalEmissions == null ? '—' : r.totalEmissions!.toStringAsFixed(2),
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
  final Widget child; // the expanded content (your per-item list)

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // was 14
              child: Row(
                children: [
                  Container(
                    width: 32, // was 40
                    height: 32, // was 40
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF3C4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long, size: 18, color: Color(0xFFFFC107)), // reduced glyph
                  ),
                  const SizedBox(width: 10), // was 12
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total CO₂e',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
                    child: const Icon(Icons.expand_more, size: 22), // was 26
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) const Divider(height: 1),

          AnimatedCrossFade(
            crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
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
          onPressed: () => Navigator.of(context).pop(), // cancel
        ),
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true, // ✅ start content right under the AppBar
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
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
                      onPressed: () => Navigator.of(context).pop(_ConfirmAction.retry),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFFFC107)),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(_ConfirmAction.confirm),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
