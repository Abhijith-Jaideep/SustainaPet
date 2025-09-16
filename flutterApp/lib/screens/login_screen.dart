import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/base_url.dart';
import '../api/pawprint_api.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _createFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  final _devFormKey = GlobalKey<FormState>();
  final _devIdCtrl = TextEditingController();

  late final PawprintApi api;

  bool _loading = false;
  bool _showDev = false;

  @override
  void initState() {
    super.initState();
    api = PawprintApi(pickBaseUrl());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _devIdCtrl.dispose();
    super.dispose();
  }

  /// Create user on the backend and persist userid + name locally.
  Future<void> _createUser() async {
    if (!_createFormKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final name = _nameCtrl.text.trim();

      // Create the user on the backend
      final created = await api.createUser(name: name);

      // Best-effort: assign some starter quests, but don't fail onboarding if it breaks
      try {
        await api.assignRandomQuests(
          userid: created.userid,
          count: 3,
          difficulty: const ['Easy', 'Medium'],
        );
      } catch (e) {
        // Log or toast if you want, but do not rethrow
        // debugPrint('assignRandomQuests failed: $e');
      }

      // Persist locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', created.userid);
      await prefs.setString('userName', created.name);

      if (!mounted) return;
      setState(() => _loading = false);
      widget.onLoginSuccess();  // navigate to Home
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account creation failed: $e')),
      );
    }
  }


  Future<void> _devLogin() async {
    if (!_devFormKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final id = int.parse(_devIdCtrl.text.trim());
      final user = await api.getUser(id); // validate against backend

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', user.userid);      // store as INT
      await prefs.setString('userName', user.name);   // handy for greetings

      if (!mounted) return;
      setState(() => _loading = false);
      widget.onLoginSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dev login failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF0FFF4);
    const card = Colors.white;
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
                // ---------- Create Profile Card ----------
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
                    key: _createFormKey,
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
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1E63FF), width: 1.6),
                            ),
                          ),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) return 'Name is required';
                            if (v.length > 16) return 'Max 16 characters';
                            return null;
                          },
                          onFieldSubmitted: (_) => _createUser(),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _createUser,
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
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text(
                              "Create & Continue",
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

                // ---------- Dev toggle ----------
                TextButton.icon(
                  onPressed: () => setState(() => _showDev = !_showDev),
                  icon: const Icon(Icons.developer_mode),
                  label: Text(_showDev ? 'Hide Developer Login' : 'Show Developer Login'),
                ),

                // ---------- Dev Login Card ----------
                if (_showDev)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                      key: _devFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            "Developer Login",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Existing User ID",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _devIdCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              hintText: "e.g., 1",
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF1E63FF), width: 1.6),
                              ),
                            ),
                            validator: (val) {
                              final v = val?.trim() ?? '';
                              if (v.isEmpty) return 'User ID is required';
                              if (int.tryParse(v) == null) return 'Enter a valid number';
                              return null;
                            },
                            onFieldSubmitted: (_) => _devLogin(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _devLogin,
                              icon: const Icon(Icons.login),
                              label: const Text("Use this user"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
                const Text(
                  "We’ll create your account on the server and store your user ID locally. "
                      "Developer Login lets you use an existing user ID.",
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
