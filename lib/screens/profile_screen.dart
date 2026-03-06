import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  User? _user;
  Map<String, dynamic> _firestoreData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _loadProfile();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .get();
        if (doc.exists && mounted) {
          setState(() => _firestoreData = doc.data() ?? {});
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isLoading = false);
      _animController.forward();
    }
  }

  String get _displayName =>
      _firestoreData['displayName'] ??
      _firestoreData['name'] ??
      _user?.displayName ??
      _user?.email?.split('@').first ??
      'User';

  String get _email => _user?.email ?? _firestoreData['email'] ?? '—';

  String? get _photoUrl => _user?.photoURL ?? _firestoreData['photoUrl'];

  String get _joinedDate {
    final ts = _firestoreData['createdAt'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return 'Joined ${months[dt.month - 1]} ${dt.year}';
    }
    final meta = _user?.metadata.creationTime;
    if (meta != null) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return 'Joined ${months[meta.month - 1]} ${meta.year}';
    }
    return 'Finzo Member';
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EFE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0EFE9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Avatar + Name Header ───────────────
                      _buildProfileHeader(),
                      const SizedBox(height: 20),

                      // ── Stats Row ──────────────────────────
                      _StatsRow(firestoreData: _firestoreData),
                      const SizedBox(height: 24),

                      // ── Account Section ────────────────────
                      _SectionLabel('Account'),
                      const SizedBox(height: 10),
                      _InfoCard(children: [
                        _InfoTile(
                          icon: Icons.person_outline_rounded,
                          label: 'Full Name',
                          value: _displayName,
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: _email,
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.verified_user_outlined,
                          label: 'Account Status',
                          value: _user?.emailVerified == true
                              ? 'Verified ✓'
                              : 'Not Verified',
                          valueColor: _user?.emailVerified == true
                              ? const Color(0xFF4CAF50)
                              : Colors.orange,
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // ── Budget Preferences ─────────────────
                      _SectionLabel('Budget Preferences'),
                      const SizedBox(height: 10),
                      _InfoCard(children: [
                        _InfoTile(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Monthly Budget',
                          value: _firestoreData['monthlyBudget'] != null
                              ? '₹${_firestoreData['monthlyBudget']}'
                              : '—',
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.flag_outlined,
                          label: 'Savings Goal',
                          value: _firestoreData['savingsGoal'] != null
                              ? '₹${_firestoreData['savingsGoal']}'
                              : '—',
                        ),
                        _divider(),
                        _InfoTile(
                          icon: Icons.notifications_outlined,
                          label: 'Alerts',
                          value: _firestoreData['alertsEnabled'] == true
                              ? 'Enabled'
                              : 'Disabled',
                          valueColor:
                              _firestoreData['alertsEnabled'] == true
                                  ? const Color(0xFF4CAF50)
                                  : Colors.grey,
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // ── App Section ────────────────────────
                      _SectionLabel('App'),
                      const SizedBox(height: 10),
                      _InfoCard(children: [
                        _ActionTile(
                          icon: Icons.shield_outlined,
                          label: 'Privacy Policy',
                          onTap: () {},
                        ),
                        _divider(),
                        _ActionTile(
                          icon: Icons.help_outline_rounded,
                          label: 'Help & Support',
                          onTap: () {},
                        ),
                        _divider(),
                        _ActionTile(
                          icon: Icons.info_outline_rounded,
                          label: 'App Version',
                          trailing: const Text('1.0.0',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 13)),
                          onTap: null,
                        ),
                      ]),
                      const SizedBox(height: 28),

                      // ── Sign Out ───────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout_rounded,
                              color: Colors.white, size: 18),
                          label: const Text('Sign Out',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[400],
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ── Clean profile header (no dark background) ─────────────
  Widget _buildProfileHeader() {
    final initials = _displayName.isNotEmpty
        ? _displayName[0].toUpperCase()
        : 'U';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border:
                  Border.all(color: const Color(0xFF4CAF50), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ],
            ),
            child: ClipOval(
              child: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? Image.network(
                      _photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _avatarFallback(initials),
                    )
                  : _avatarFallback(initials),
            ),
          ),
          const SizedBox(width: 16),

          // Name + email + joined
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Colors.black87),
                ),
                const SizedBox(height: 3),
                Text(
                  _email,
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _joinedDate,
                    style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String initial) {
    return Container(
      color: const Color(0xFFE8F5E9),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
              color: Color(0xFF4CAF50),
              fontSize: 26,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _divider() => Divider(
      height: 1, thickness: 1, color: Colors.grey[100], indent: 52);
}

// ── Stats Row ────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final Map<String, dynamic> firestoreData;
  const _StatsRow({required this.firestoreData});

  @override
  Widget build(BuildContext context) {
    final budget = firestoreData['monthlyBudget'] ?? 0;
    final spent = firestoreData['totalSpent'] ?? 0;
    final saved = (budget - spent).clamp(0, double.infinity);

    return Row(
      children: [
        _StatBox(label: 'Budget', value: '₹$budget', color: Colors.blue),
        const SizedBox(width: 12),
        _StatBox(label: 'Spent', value: '₹$spent', color: Colors.orange),
        const SizedBox(width: 12),
        _StatBox(
            label: 'Saved',
            value: '₹$saved',
            color: const Color(0xFF4CAF50)),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Reusable Widgets ─────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2));
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EFE9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.grey[600]),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: valueColor ?? Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EFE9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: Colors.grey[600]),
            ),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            trailing ??
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }
}