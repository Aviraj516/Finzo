import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';
import '../services/auth_service.dart';
import 'analytics_screen.dart';
import 'goals_screen.dart';
import 'streak_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';

// Simple model for a transaction
class _Transaction {
  final String merchant;
  final double amount;
  final DateTime time;
  _Transaction({required this.merchant, required this.amount, required this.time});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────
  double income = 0;
  double totalSpent = 0;
  int xp = 0;
  int streak = 0;
  bool isLoading = false;
  String plantStage = '🌱';
  String plantLabel = 'Seed';
  int _selectedIndex = 0;

  // ── Firebase user info ────────────────────────────────
  User? _firebaseUser;
  String _displayName = 'Hey there!';
  String? _photoUrl;
  String _firstLetter = 'U';

  // SMS + Transactions
  final SmsService _smsService = SmsService();
  final List<_Transaction> _transactions = [];

  // Spike warnings
  List<String> _spendingWarnings = [];
  double _previousTotalSpent = 0;

  late AnimationController _plantAnim;
  late Animation<double> _scaleAnim;

  // ── Lifecycle ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _plantAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(parent: _plantAnim, curve: Curves.elasticOut);
    _plantAnim.forward();

    // ── Listen to auth state changes (login / logout / token refresh)
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _firebaseUser = null;
          _displayName  = 'Hey there!';
          _photoUrl     = null;
          _firstLetter  = 'U';
        });
      } else {
        _loadUserProfile();
        _loadDashboard();
      }
    });

    _loadUserProfile();
    _loadDashboard();

    _smsService.startListening(
      onTransaction: (merchant, amount) {
        setState(() {
          _transactions.insert(
            0,
            _Transaction(merchant: merchant, amount: amount, time: DateTime.now()),
          );
          totalSpent += amount;
          _updatePlant();
          _checkSpendingSpike(merchant, amount);
        });
      },
    );
  }

  // ── Load Firebase user profile ────────────────────────
  Future<void> _loadUserProfile() async {
    // Reload to get latest displayName/photoURL from Firebase server
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _firebaseUser = user);

    // First use FirebaseAuth data immediately
    final authName = user.displayName ?? user.email?.split('@').first ?? 'there';
    setState(() {
      _displayName = authName;
      _photoUrl    = user.photoURL;
      _firstLetter = authName.isNotEmpty ? authName[0].toUpperCase() : 'U';
    });

    // Then enrich from Firestore if available
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final fsName = (data['displayName'] as String?)?.trim() ?? '';
        if (fsName.isNotEmpty) {
          setState(() {
            _displayName = fsName;
            _firstLetter = fsName[0].toUpperCase();
          });
        }
        // photoUrl override from Firestore if set
        final fsPhoto = data['photoUrl'] as String?;
        if (fsPhoto != null && fsPhoto.isNotEmpty) {
          setState(() => _photoUrl = fsPhoto);
        }
      }
    } catch (_) {}
  }

  // ── Load dashboard data ───────────────────────────────
  // ── Load dashboard data ─────────────────────────────
  Future<void> _loadDashboard() async {
    try {
      final data = await ApiService.getDashboardData();
      if (!mounted) return;
      if (data['error'] == null) {
        setState(() {
          income     = ((data['income']     ?? 0) as num).toDouble();
          totalSpent = ((data['totalSpent'] ?? 0) as num).toDouble();
          xp         = ((data['xp']         ?? 0) as num).toInt();
          streak     = ((data['streak']     ?? 0) as num).toInt();
          _updatePlant();
          _plantAnim..reset()..forward();
        });
      }
      // Timeout/network errors silently ignored on background load.
      // User can tap the refresh button on the balance card to retry.
    } catch (_) {
      // Silent — no snackbar for background dashboard load
    }
  }

  @override
  void dispose() {
    _plantAnim.dispose();
    super.dispose();
  }

  // ── Plant Logic ───────────────────────────────────────
  void _updatePlant() {
    if (xp <= 30) {
      plantStage = '🌱';
      plantLabel = 'Seed';
    } else if (xp <= 70) {
      plantStage = '🌿';
      plantLabel = 'Sapling';
    } else if (xp <= 120) {
      plantStage = '🌳';
      plantLabel = 'Small Tree';
    } else {
      plantStage = '🌴';
      plantLabel = 'Lush Tree';
    }
  }

  // ── Spending Spike Detection ──────────────────────────
  void _checkSpendingSpike(String merchant, double amount) {
    final List<String> warnings = [];

    if (income > 0 && amount > income * 0.20) {
      warnings.add(
          '🚨 Big spend! ₹${amount.toStringAsFixed(0)} at $merchant is ${((amount / income) * 100).toStringAsFixed(0)}% of your income');
    }
    if (amount > 2000) {
      warnings.add(
          '⚠️ Large transaction: ₹${amount.toStringAsFixed(0)} at $merchant');
    }
    if (_previousTotalSpent > 0) {
      final spike =
          ((totalSpent - _previousTotalSpent) / _previousTotalSpent) * 100;
      if (spike > 30) {
        warnings.add(
            '📈 Spending spike! Total jumped ${spike.toStringAsFixed(0)}% with this transaction');
      }
    }
    final budget = income * 0.8;
    if (income > 0 && totalSpent > budget && _previousTotalSpent <= budget) {
      warnings.add("🔴 Budget alert: You've spent over 80% of your income!");
    }

    _previousTotalSpent = totalSpent - amount;

    if (warnings.isNotEmpty) {
      setState(() => _spendingWarnings = warnings);
      _showSnack(warnings.first, Colors.orange.shade800);
    }
  }

  // ── Open Profile Screen ───────────────────────────────
  void _openProfile() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const ProfileScreen(),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    ).then((_) async {
      // Reload name + photo when returning from ProfileScreen
      await _loadUserProfile();
      if (mounted) setState(() {});
    });
  }

  // ── Setup Income Dialog ────────────────────────────────
  void _showIncomeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.account_balance_wallet, color: Color(0xFF4CAF50)),
            SizedBox(width: 8),
            Text('Set Monthly Income'),
          ],
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 45000',
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final val = double.tryParse(controller.text);
              if (val == null) return;
              Navigator.pop(context);
              setState(() => isLoading = true);
              final result = await ApiService.setupIncome(val);
              setState(() {
                isLoading = false;
                if (result['error'] == null) {
                  income = val;
                  totalSpent = 0;
                  xp = 0;
                  streak = 0;
                  _updatePlant();
                  _plantAnim..reset()..forward();
                }
              });
              _showSnack(
                result['error'] != null
                    ? '❌ ${result['error']}'
                    : '✅ Income set to ₹$val',
                result['error'] != null ? Colors.red : const Color(0xFF4CAF50),
              );
            },
            child: const Text('Set Income',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Add Expense Dialog ─────────────────────────────────
  void _showExpenseDialog() {
    final amountCtrl = TextEditingController();
    String selectedCategory = 'Food';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.receipt_long, color: Color(0xFF5C6BC0)),
              SizedBox(width: 8),
              Text('Add Expense'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: ['Food', 'Shopping', 'Travel'].map((c) {
                  return DropdownMenuItem(value: c, child: Text(c));
                }).toList(),
                onChanged: (v) =>
                    setStateDialog(() => selectedCategory = v ?? 'Food'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: 'Amount',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null) return;
                Navigator.pop(context);
                setState(() => isLoading = true);
                final result =
                    await ApiService.addExpense(selectedCategory, amt);
                setState(() {
                  isLoading = false;
                  if (result['error'] == null) {
                    _previousTotalSpent = totalSpent;
                    totalSpent += amt;
                    xp = ((result['xp'] ?? xp) as num).toInt();
                    _updatePlant();
                    _plantAnim..reset()..forward();
                    _checkSpendingSpike(selectedCategory, amt);
                  }
                });
                _showSnack(
                  result['error'] != null
                      ? '❌ ${result['error']}'
                      : '💸 ₹$amt added | Risk: ${result['risk']}% | XP: ${result['xp']}',
                  result['error'] != null
                      ? Colors.red
                      : const Color(0xFF4CAF50),
                );
              },
              child:
                  const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EFE9),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.home_rounded, 'Home'),
                _navItem(1, Icons.bar_chart_rounded, 'Analytics'),
                _navItem(2, Icons.flag_rounded, 'Goals'),
                _navItem(3, Icons.local_fire_department_rounded, 'Streak'),
                _navItem(4, Icons.card_giftcard_rounded, 'Rewards'),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeBody(),
            const AnalyticsScreen(),
            const GoalsScreen(),
            const StreakScreen(),
            const RewardsScreen(),
          ],
        ),
      ),
    );
  }

  // ── Home Body ──────────────────────────────────────────
  Widget _buildHomeBody() {
    final balance = income - totalSpent;
    final double growthPercent =
        ((xp / 200) * 100).clamp(0.0, 100.0).toDouble();

    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF4CAF50)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // ── Header ──────────────────────────────────
          Row(
            children: [
              const Text(
                'Finzo',
                style:
                    TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.eco, color: Color(0xFF4CAF50), size: 26),
              const Spacer(),
              // ── Profile Avatar Button ──────────────
              GestureDetector(
                onTap: _openProfile,
                child: _buildAvatarWidget(size: 40),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── User greeting (Firebase name) ────────────
          Row(
            children: [
              GestureDetector(
                onTap: _openProfile,
                child: _buildAvatarWidget(size: 44),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hey, $_displayName!',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department,
                          color: Colors.orange, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$plantLabel · Streak: $streak',
                        style: const TextStyle(
                            color: Color(0xFF4CAF50), fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              _iconBtn(Icons.notifications_none, () {}),
              const SizedBox(width: 8),
              _iconBtn(Icons.settings_outlined, _showIncomeDialog),
            ],
          ),
          const SizedBox(height: 20),

          // ── Money Plant Card ─────────────────────────
          _buildPlantCard(growthPercent),
          const SizedBox(height: 20),

          // ── Spending Spike Warnings ──────────────────
          if (_spendingWarnings.isNotEmpty) ...[
            ..._spendingWarnings.map((w) => _buildWarningBanner(w)),
            const SizedBox(height: 4),
          ],

          // ── Balance Card ─────────────────────────────
          _buildBalanceCard(balance),
          const SizedBox(height: 20),

          // ── Recent Transactions ──────────────────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long,
                        color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: 8),
                    const Text('Recent Transactions',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_transactions.length} total',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _transactions.isEmpty
                    ? Center(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            children: [
                              Icon(Icons.sms_outlined,
                                  size: 40, color: Colors.grey[300]),
                              const SizedBox(height: 8),
                              Text(
                                'No transactions yet\nSMS listener is active',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey[400], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _transactions.length > 5
                            ? 5
                            : _transactions.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: Colors.grey[100], height: 1),
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          return _transactionTile(tx);
                        },
                      ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Action Buttons ───────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _actionBtn('💰', 'Set Income', _showIncomeDialog,
                  const Color(0xFFE8F5E9)),
              _actionBtn('💸', 'Expense', _showExpenseDialog,
                  const Color(0xFFE8EAF6)),
              _actionBtn('📊', 'Invest', () {}, const Color(0xFFFFF8E1)),
              _actionBtn('🎯', 'Goals', () {
                setState(() => _selectedIndex = 2);
              }, const Color(0xFFFCE4EC)),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── Profile Avatar Widget ─────────────────────────────
  // Shows real photo from Firebase or initial letter fallback
  Widget _buildAvatarWidget({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF4CAF50), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withOpacity(0.25),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: _photoUrl != null && _photoUrl!.isNotEmpty
            ? Image.network(
                _photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarFallback(size),
              )
            : _avatarFallback(size),
      ),
    );
  }

  Widget _avatarFallback(double size) {
    return Container(
      color: const Color(0xFF2E4A2E),
      child: Center(
        child: Text(
          _firstLetter,
          style: TextStyle(
            color: const Color(0xFF4CAF50),
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Plant Card ────────────────────────────────────────
  Widget _buildPlantCard(double growthPercent) {
    final List<_LeafData> leaves = _getLeaves();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F14),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF4CAF50).withOpacity(0.18),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: const Color(0xFF4CAF50), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.eco, color: Color(0xFF4CAF50), size: 14),
                const SizedBox(width: 6),
                Text(plantLabel,
                    style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ScaleTransition(
            scale: _scaleAnim,
            child: SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _TreePainter(leaves: leaves, xp: xp),
                size: const Size(double.infinity, 220),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.spa,
                        color: Color(0xFF4CAF50), size: 16),
                    const SizedBox(width: 6),
                    const Text('Growth Progress',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('$xp XP / 200 MAX',
                        style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: growthPercent / 100,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4CAF50)),
                    minHeight: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_LeafData> _getLeaves() {
    if (xp <= 30) {
      return [
        _LeafData(-14, -20, 22, -0.45),
        _LeafData(12, -38, 18, 0.35),
      ];
    }
    if (xp <= 70) {
      final double t = ((xp - 31) / 39.0).clamp(0.0, 1.0);
      final double s = 26 + t * 8;
      return [
        _LeafData(-20, -30, s, -0.5),
        _LeafData(14, -52, s - 4, 0.42),
        _LeafData(-10, -72, s - 6, -0.25),
      ];
    }
    if (xp <= 120) {
      final double t = ((xp - 71) / 49.0).clamp(0.0, 1.0);
      final double s = 32 + t * 10;
      return [
        _LeafData(-28, -38, s, -0.55),
        _LeafData(18, -62, s - 2, 0.48),
        _LeafData(-16, -86, s - 4, -0.28),
        _LeafData(22, -108, s - 6, 0.55),
        _LeafData(-12, -128, s - 8, -0.2),
      ];
    }
    final double t = ((xp - 121) / 79.0).clamp(0.0, 1.0);
    final double s = 44 + t * 10;
    final leaves = <_LeafData>[
      _LeafData(-34, -42, s, -0.58),
      _LeafData(22, -66, s - 2, 0.5),
      _LeafData(-20, -92, s - 4, -0.3),
      _LeafData(26, -116, s - 6, 0.55),
      _LeafData(-28, -138, s - 8, -0.45),
      _LeafData(18, -158, s - 10, 0.38),
      _LeafData(-14, -176, s - 12, -0.22),
    ];
    if (xp > 180) leaves.add(_LeafData(10, -194, s - 14, 0.3));
    return leaves;
  }

  Widget _buildBalanceCard(double balance) {
    final isPositive = balance >= 0;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [const Color(0xFF7f0000), const Color(0xFFb71c1c)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color:
                  (isPositive ? Colors.green : Colors.red).withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('TOTAL BALANCE',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.8,
                      color: Colors.white60)),
              const Spacer(),
              GestureDetector(
                onTap: _loadDashboard,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Colors.white70, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹${balance.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.white : Colors.red[100]),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _balancePill('Income', income, Colors.greenAccent,
                  Icons.arrow_downward),
              const SizedBox(width: 12),
              _balancePill('Expenses', totalSpent, Colors.pinkAccent,
                  Icons.arrow_upward),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balancePill(
      String label, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white60)),
                Text('₹${amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningBanner(String message) {
    final isRed = message.startsWith('🔴') || message.startsWith('🚨');
    final color = isRed ? const Color(0xFFb71c1c) : const Color(0xFFE65100);
    final bgColor =
        isRed ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0);
    final border =
        isRed ? const Color(0xFFEF9A9A) : const Color(0xFFFFCC80);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        children: [
          Text(message.substring(0, 2), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message.substring(2).trim(),
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => setState(
                () => _spendingWarnings.removeWhere((w) => w == message)),
            child: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Icon(icon, size: 20, color: Colors.grey[700]),
      ),
    );
  }

  Widget _actionBtn(
      String emoji, String label, VoidCallback onTap, Color bg) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4CAF50).withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 22,
                color: isSelected
                    ? const Color(0xFF4CAF50)
                    : Colors.grey[400]),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF4CAF50)
                        : Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _transactionTile(_Transaction tx) {
    IconData icon = Icons.shopping_bag_outlined;
    Color iconColor = const Color(0xFF5C6BC0);
    Color iconBg = const Color(0xFFE8EAF6);

    final m = tx.merchant.toLowerCase();
    if (m.contains('amazon') || m.contains('flipkart') || m.contains('shop')) {
      icon = Icons.shopping_cart_outlined;
      iconColor = const Color(0xFF5C6BC0);
      iconBg = const Color(0xFFE8EAF6);
    } else if (m.contains('uber') ||
        m.contains('ola') ||
        m.contains('travel')) {
      icon = Icons.directions_car_outlined;
      iconColor = const Color(0xFF212121);
      iconBg = const Color(0xFFF5F5F5);
    } else if (m.contains('zomato') ||
        m.contains('swiggy') ||
        m.contains('food')) {
      icon = Icons.fastfood_outlined;
      iconColor = const Color(0xFFE64A19);
      iconBg = const Color(0xFFFBE9E7);
    } else if (m.contains('starbucks') ||
        m.contains('cafe') ||
        m.contains('coffee')) {
      icon = Icons.local_cafe_outlined;
      iconColor = const Color(0xFF5D4037);
      iconBg = const Color(0xFFEFEBE9);
    } else if (m.contains('paytm') ||
        m.contains('gpay') ||
        m.contains('phonepe') ||
        m.contains('upi')) {
      icon = Icons.account_balance_wallet_outlined;
      iconColor = const Color(0xFF4CAF50);
      iconBg = const Color(0xFFE8F5E9);
    }

    final diff = DateTime.now().difference(tx.time);
    String timeStr;
    if (diff.inMinutes < 1) {
      timeStr = 'Just now';
    } else if (diff.inMinutes < 60) {
      timeStr = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeStr = '${diff.inHours}h ago';
    } else {
      timeStr = '${diff.inDays}d ago';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.merchant,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                Text(timeStr,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ),
          Text(
            '- ₹${tx.amount.toStringAsFixed(0)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Leaf data model
// ─────────────────────────────────────────────────────────────
class _LeafData {
  final double dx;
  final double dy;
  final double size;
  final double angle;
  const _LeafData(this.dx, this.dy, this.size, this.angle);
}

// ─────────────────────────────────────────────────────────────
// Tree CustomPainter
// ─────────────────────────────────────────────────────────────
class _TreePainter extends CustomPainter {
  final List<_LeafData> leaves;
  final int xp;
  const _TreePainter({required this.leaves, required this.xp});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height;

    final potPaint = Paint()..color = const Color(0xFF7B3FC4);
    final potHighlight = Paint()..color = const Color(0xFF9B5FE4);
    final dirtPaint = Paint()..color = const Color(0xFF5C3A1E);

    final potPath = Path()
      ..moveTo(cx - 38, bottom - 28)
      ..lineTo(cx + 38, bottom - 28)
      ..lineTo(cx + 28, bottom)
      ..lineTo(cx - 28, bottom)
      ..close();
    canvas.drawPath(potPath, potPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, bottom - 28), width: 82, height: 14),
        const Radius.circular(7),
      ),
      potHighlight,
    );

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, bottom - 28), width: 72, height: 10),
      dirtPaint,
    );

    final rupeePainter = TextPainter(
      text: const TextSpan(
        text: '₹',
        style: TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 14,
            fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rupeePainter.paint(
        canvas, Offset(cx - rupeePainter.width / 2, bottom - 22));

    final stemHeight = 40.0 + (leaves.length * 22.0);
    final stemPaint = Paint()
      ..color = const Color(0xFF2E8B2E)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(cx, bottom - 32),
      Offset(cx, bottom - 32 - stemHeight),
      stemPaint,
    );

    for (final leaf in leaves) {
      _drawLeaf(canvas, cx, bottom - 32 - stemHeight * 0.5, leaf.dx,
          leaf.dy * (stemHeight / 150), leaf.size, leaf.angle);
    }

    final coinCenter = Offset(cx, bottom - 32 - stemHeight - 12);
    canvas.drawCircle(
        coinCenter, 12, Paint()..color = const Color(0xFFFFD700));
    canvas.drawCircle(
        coinCenter,
        12,
        Paint()
          ..color = const Color(0xFFFF8C00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    final coinPainter = TextPainter(
      text: const TextSpan(
        text: '₹',
        style: TextStyle(
            color: Color(0xFF7B3F00),
            fontSize: 12,
            fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    coinPainter.paint(
        canvas,
        Offset(coinCenter.dx - coinPainter.width / 2,
            coinCenter.dy - coinPainter.height / 2));

    if (xp > 30) {
      _drawSparkle(
          canvas, cx - 52, bottom - 85, 5, const Color(0xFFFFD700));
      _drawSparkle(
          canvas, cx + 50, bottom - 105, 4, const Color(0xFF4CAF50));
    }
    if (xp > 70) {
      _drawHeart(canvas, cx + 60, bottom - 140, const Color(0xFF4CAF50));
      _drawStar(canvas, cx - 62, bottom - 58, 7, const Color(0xFF8B6914));
    }
    if (xp > 120) {
      _drawSparkle(
          canvas, cx + 55, bottom - 165, 6, const Color(0xFFFFD700));
      _drawStar(
          canvas, cx + 65, bottom - 55, 5, const Color(0xFFFFD700));
      _drawSparkle(
          canvas, cx - 58, bottom - 175, 4, const Color(0xFF66BB6A));
    }
  }

  void _drawLeaf(Canvas canvas, double stemX, double stemMidY, double dx,
      double dy, double w, double angle) {
    canvas.save();
    canvas.translate(stemX + dx * 0.6, stemMidY + dy);
    canvas.rotate(angle);

    final leafPaint = Paint()..color = const Color(0xFF4CAF50);
    final leafHighlight = Paint()..color = const Color(0xFF66BB6A);
    final veinPaint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final rect =
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.55);
    canvas.drawOval(rect, leafPaint);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(-w * 0.1, -w * 0.06),
            width: w * 0.55,
            height: w * 0.28),
        leafHighlight);
    canvas.drawLine(Offset(-w * 0.4, 0), Offset(w * 0.4, 0), veinPaint);
    canvas.restore();
  }

  void _drawSparkle(
      Canvas canvas, double x, double y, double r, Color color) {
    final p = Paint()..color = color;
    canvas.drawCircle(Offset(x, y), r * 0.4, p);
    final sp = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 4; i++) {
      final angle = i * 3.14159 / 2;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + r * 1.2 * cos(angle), y + r * 1.2 * sin(angle)),
        sp,
      );
    }
  }

  void _drawHeart(Canvas canvas, double x, double y, Color color) {
    final p = Paint()..color = color;
    final path = Path();
    path.moveTo(x, y + 5);
    path.cubicTo(x - 10, y - 5, x - 18, y + 2, x, y + 14);
    path.cubicTo(x + 18, y + 2, x + 10, y - 5, x, y + 5);
    canvas.drawPath(path, p);
  }

  void _drawStar(
      Canvas canvas, double x, double y, double r, Color color) {
    final p = Paint()..color = color;
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outer = i * 4 * 3.14159 / 5 - 3.14159 / 2;
      final inner = outer + 2 * 3.14159 / 5;
      if (i == 0) {
        path.moveTo(x + r * cos(outer), y + r * sin(outer));
      } else {
        path.lineTo(x + r * cos(outer), y + r * sin(outer));
      }
      path.lineTo(x + r * 0.4 * cos(inner), y + r * 0.4 * sin(inner));
    }
    path.close();
    canvas.drawPath(path, p);
  }

  double cos(double a) => _mathCos(a);
  double sin(double a) => _mathSin(a);

  static double _mathCos(double a) {
    a = a % (2 * 3.14159265358979);
    double result = 1;
    double term = 1;
    for (int i = 1; i <= 10; i++) {
      term *= -a * a / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _mathSin(double a) {
    a = a % (2 * 3.14159265358979);
    double result = a;
    double term = a;
    for (int i = 1; i <= 10; i++) {
      term *= -a * a / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  @override
  bool shouldRepaint(_TreePainter old) => old.xp != xp;
}