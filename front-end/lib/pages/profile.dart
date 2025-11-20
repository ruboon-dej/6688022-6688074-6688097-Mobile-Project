import 'package:flutter/material.dart';
import '../config.dart';
import '../auth_store.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String displayName = 'Nattachai';
  String email = 'you@example.com';
  String? avatarUrl;
  String bio = 'Your bio have not been set yet.';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await apiGet('/profile');
      if (!mounted) return;
      setState(() {
        displayName = (data['display_name'] ?? displayName).toString();
        email       = (data['email'] ?? email).toString();
        avatarUrl   = (data['avatar_url'] ?? '') as String?;
        final b     = (data['bio'] ?? '').toString().trim();
        if (b.isNotEmpty) bio = b;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _editProfileDialog() async {
    final nameCtrl = TextEditingController(text: displayName);
    final bioCtrl  = TextEditingController(text: bio == 'the cyber security experts' ? '' : bio);

    final dense = const InputDecorationTheme(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: Theme.of(context).copyWith(inputDecorationTheme: dense),
        child: AlertDialog(
          title: const Text('Edit profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                // ✅ Make Bio the same single-line height as Name
                TextField(
                  controller: bioCtrl,
                  decoration: const InputDecoration(labelText: 'Bio (optional)'),
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final newName = nameCtrl.text.trim();
      final newBio  = bioCtrl.text.trim();
      if (newName.isEmpty) return;
      await apiPut('/profile', {'display_name': newName, 'bio': newBio});
      if (!mounted) return;
      setState(() { displayName = newName; bio = newBio; });
    }
  }

  void _logout() async {
    try { await AuthStore.logout(); } catch (_) {}
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged out')));
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final avatarR = screenW * 0.22;
    final bioText = bio.trim().isEmpty ? 'Bio not set yet' : bio;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF7F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.pinkAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _logout,
            child: const Text('Logout',
                style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Card stack (allow overflow for the pencil badge)
                  SizedBox(
                    width: screenW * 0.8,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        // Rounded sky image
                        AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset('assets/images/sky.png', fit: BoxFit.cover),
                          ),
                        ),

                        // Pencil badge (white circle)
                        Positioned(
                          top: -12,
                          right: -12,
                          child: Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            elevation: 4,
                            child: InkWell(
                              onTap: _editProfileDialog,
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Image.asset('assets/icons/Pencil.png', width: 30, height: 30),
                              ),
                            ),
                          ),
                        ),

                        // Overlapping avatar with white ring
                        Positioned(
                          bottom: -avatarR * 0.6,
                          child: CircleAvatar(
                            radius: avatarR + 6,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: avatarR,
                              backgroundColor: Colors.transparent,
                              backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                                  ? NetworkImage(avatarUrl!)
                                  : const AssetImage('assets/images/BigProfile.png') as ImageProvider,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Space for the overlap
                  SizedBox(height: avatarR * 0.9 + 20),

                  // Name
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFE57373)),
                  ),
                  const SizedBox(height: 4),

                  // Bio (or placeholder) – display size unchanged (14)
                  Text(
                    bioText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF80CBC4),
                      fontStyle: bioText == 'Bio not set yet' ? FontStyle.italic : FontStyle.normal,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
