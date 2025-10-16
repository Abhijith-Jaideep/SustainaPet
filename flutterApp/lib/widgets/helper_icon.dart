// lib/widgets/helper_icon.dart
import 'package:flutter/material.dart';

/// Reusable help dialog that shows an image.
Future<void> showHelpImageDialog(
    BuildContext context, {
      required String asset,
      String title = 'How this page works',
    }) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(
              children: [
                const Icon(Icons.help_outline, color: Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Image
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                minScale: 0.6,
                maxScale: 3.5,
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Help image not found.'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

/// Simple “?” icon that always shows the same asset.
class HelpIcon extends StatelessWidget {
  final String assetPath; // e.g. assets/help/home.jpg
  final String title;
  final String tooltip;

  const HelpIcon({
    super.key,
    required this.assetPath,
    this.title = 'How this page works',
    this.tooltip = 'Help',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.help_outline),
      onPressed: () =>
          showHelpImageDialog(context, asset: assetPath, title: title),
    );
  }
}

/// Tab-aware “?” icon. Provide a map of tabIndex -> asset path.
/// If the active index isn’t found, it uses [fallbackAsset] (if given).
class HelpIconTabAware extends StatefulWidget {
  final TabController controller;
  final Map<int, String> assetsByIndex;
  final Map<int, String>? titlesByIndex;
  final String? fallbackAsset;
  final String tooltip;

  const HelpIconTabAware({
    super.key,
    required this.controller,
    required this.assetsByIndex,
    this.titlesByIndex,
    this.fallbackAsset,
    this.tooltip = 'Help',
  });

  @override
  State<HelpIconTabAware> createState() => _HelpIconTabAwareState();
}

class _HelpIconTabAwareState extends State<HelpIconTabAware> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.controller.index;
    widget.controller.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!mounted) return;
    if (_index != widget.controller.index) {
      setState(() => _index = widget.controller.index);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      icon: const Icon(Icons.help_outline),
      onPressed: () {
        final asset =
            widget.assetsByIndex[_index] ?? widget.fallbackAsset;
        if (asset == null) return;
        final title =
        widget.titlesByIndex != null ? (widget.titlesByIndex![_index] ?? 'How this page works') : 'How this page works';
        showHelpImageDialog(context, asset: asset, title: title);
      },
    );
  }
}
