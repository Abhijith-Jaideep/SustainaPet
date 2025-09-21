import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class GroceryScannerScreen extends StatefulWidget {
  const GroceryScannerScreen({super.key});

  @override
  State<GroceryScannerScreen> createState() => _GroceryScannerScreenState();
}

class _GroceryScannerScreenState extends State<GroceryScannerScreen> {
  String? _pickedFile;

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf','jpg','png'],
      );

      if (!mounted) return;

      if (result != null && result.files.single.path != null) {
        setState(() => _pickedFile = result.files.single.name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected: ${result.files.single.name}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery Receipt Scanner'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // 👈 centers vertically
            crossAxisAlignment: CrossAxisAlignment.center, // 👈 centers horizontally
            children: [
              // --- Animated gif or asset ---
              SizedBox(
                height: 200,
                child: Image.asset(
                  'assets/scan.gif', // make sure this exists & is declared in pubspec.yaml
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.document_scanner,
                    size: 80,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                "Upload your grocery receipt to begin scanning",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 32),

              // Button to pick PDF
              SizedBox(
                width: double.infinity, // 👈 makes button stretch nicely
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _pickPdf,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text(
                    "Choose PDF Receipt",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_pickedFile != null)
                Text(
                  "Selected file: $_pickedFile",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
