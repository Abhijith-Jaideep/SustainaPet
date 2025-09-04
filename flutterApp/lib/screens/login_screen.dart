import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final String userId = const Uuid().v4();
    final String name = _nameCtrl.text.trim();

    await prefs.setString('userId', userId);
    await prefs.setString('userName', name);

    if (!mounted) return;
    setState(() => _loading = false);
    widget.onLoginSuccess();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF0FFF4);      // soft mint
    const card = Colors.white;
    const primary = Color(0xFF1E63FF); // vivid blue
    const textMuted = Color(0xFF667085);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Card with just the form
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, 6),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Create your profile",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          "Your name",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameCtrl,
                          textInputAction: TextInputAction.done,
                          maxLength: 16,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(16),
                            FilteringTextInputFormatter.allow(
                              RegExp(r"[A-Za-z0-9 '.-]"),
                            ),
                          ],
                          decoration: InputDecoration(
                            counterText: "",
                            hintText: "Enter your name (max 16 chars)",
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              const BorderSide(color: primary, width: 1.6),
                            ),
                          ),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) return 'Name is required';
                            if (v.length > 16) return 'Max 16 characters';
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                                : const Text(
                              "Continue",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),
                const Text(
                  "Stored locally only. A private user ID will be created.",
                  style: TextStyle(fontSize: 12, color: textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
