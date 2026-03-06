import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with AutomaticKeepAliveClientMixin {

  Map<String, double> spent        = {'Food': 0, 'Shopping': 0, 'Travel': 0};
  Map<String, double> categoryRisk = {'Food': 0, 'Shopping': 0, 'Travel': 0};
  bool isLoading           = false;
  String aiPrediction      = '';
  String overspendingAlert = '';
  double safeDailySpend    = 0;
  double remainingBudget   = 0;
  bool _firstLoad          = true;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_firstLoad) _loadData();
    _firstLoad = false;
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final data = await ApiService.getDashboardData();
    if (!mounted) return;
    setState(() {
      isLoading = false;
      if (data['error'] == null) {
        final catSpent = data['categorySpent'] as Map<String, double>?;
        if (catSpent != null) spent = catSpent;
        final catRisk = data['categoryRisk'] as Map<String, double>?;
        if (catRisk != null) categoryRisk = catRisk;
        safeDailySpend    = data['safeDailySpend']    ?? 0;
        remainingBudget   = data['remainingBudget']   ?? 0;
        aiPrediction      = data['aiPrediction']      ?? '';
        overspendingAlert = data['overspendingAlert'] ?? '';
      }
    });
  }

  void _openProfile() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const ProfileScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _showSmsDialog() {
    final merchantCtrl = TextEditingController();
    final amountCtrl   = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('📱 SMS Expense Detection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: merchantCtrl,
              decoration: InputDecoration(
                labelText: 'Merchant Name',
                hintText: 'e.g. Amazon, Swiggy, Uber',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
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
              final merchant = merchantCtrl.text.trim();
              final amount   = double.tryParse(amountCtrl.text);
              if (merchant.isEmpty || amount == null) return;
              Navigator.pop(context);
              setState(() => isLoading = true);
              final result = await ApiService.smsExpense(amount, merchant);
              if (result['error'] == null) {
                await _loadData();
              } else {
                setState(() => isLoading = false);
              }
              _snack(
                result['error'] != null
                    ? '❌ ${result['error']}'
                    : '🤖 Detected: ${result['detected_category']} | ₹$amount added',
                result['error'] != null ? Colors.red : const Color(0xFF4CAF50),
              );
            },
            child: const Text('Detect & Add',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  double _getRisk(String category) =>
      (categoryRisk[category] ?? 0.0).clamp(0.0, 100.0).toDouble();

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final categories = [
      {'name': 'Food',     'emoji': '🍜', 'color': const Color(0xFF4CAF50), 'bg': const Color(0xFFE8F5E9)},
      {'name': 'Travel',   'emoji': '🚌', 'color': const Color(0xFF7C4DFF), 'bg': const Color(0xFFEDE7F6)},
      {'name': 'Shopping', 'emoji': '🎮', 'color': const Color(0xFFFF9800), 'bg': const Color(0xFFFFF3E0)},
    ];

    final totalSpent      = spent.values.fold(0.0, (a, b) => a + b);
    final totalForPercent = totalSpent > 0 ? totalSpent : 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF0EFE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0EFE9),
        elevation: 0,
        title: const Text('Finzo 🌿',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black54),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.sms_outlined, color: Colors.black54),
            onPressed: _showSmsDialog,
          ),
          // ── Profile Avatar Button (top-right) ──────────
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: _openProfile,
              child: _ProfileAvatar(user: _currentUser),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : RefreshIndicator(
              color: const Color(0xFF4CAF50),
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Day Forecast Card ──────────────
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Row(children: const [
                            Text('📅', style: TextStyle(fontSize: 22)),
                            SizedBox(width: 8),
                            Text('Day Forecast',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18)),
                          ]),
                          const Divider(height: 20),
                          _forecastRow('📈', 'Safe Daily Spend',
                              '₹${safeDailySpend.toStringAsFixed(0)}',
                              const Color(0xFF4CAF50)),
                          _forecastRow('🛡', 'Remaining Budget',
                              '₹${remainingBudget.toStringAsFixed(0)}',
                              Colors.blue),
                          _forecastRow(
                              '⚡',
                              'AI Prediction',
                              aiPrediction.isEmpty ? '–' : aiPrediction,
                              aiPrediction.contains('⚠')
                                  ? Colors.orange
                                  : const Color(0xFF4CAF50)),
                          if (overspendingAlert.isNotEmpty)
                            _forecastRow(
                                '⚠️', 'Alert', overspendingAlert, Colors.red),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── This Month Header ──────────────
                    Row(
                      children: [
                        const Text('📊 This Month',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                        const Spacer(),
                        GestureDetector(
                          onTap: _showSmsDialog,
                          child: const Text('+ SMS →',
                              style: TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Category Grid ──────────────────
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: categories.length,
                      itemBuilder: (_, i) {
                        final cat  = categories[i];
                        final name = cat['name'] as String;
                        final s    = spent[name] ?? 0;
                        final pct  = totalSpent > 0
                            ? ((s / totalForPercent) * 100).round()
                            : 0;
                        return _categoryCard(
                          emoji:   cat['emoji'] as String,
                          label:   name,
                          amount:  s,
                          percent: pct,
                          risk:    _getRisk(name),
                          color:   cat['color'] as Color,
                          bg:      cat['bg'] as Color,
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  // ── FIXED: long values wrap below label ───────────────────
  Widget _forecastRow(
      String icon, String label, String value, Color valueColor) {
    final isLongValue = value.length > 12;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: isLongValue
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(
                    value,
                    style: TextStyle(
                        color: valueColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    softWrap: true,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500))),
                Text(value,
                    style: TextStyle(
                        color: valueColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ],
            ),
    );
  }

  Widget _categoryCard({
    required String emoji,
    required String label,
    required double amount,
    required int percent,
    required double risk,
    required Color color,
    required Color bg,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(10)),
                child: Text(emoji, style: const TextStyle(fontSize: 18)),
              ),
              const Spacer(),
              Text('$percent%',
                  style: TextStyle(
                      color: Colors.grey[400],
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const Spacer(),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          Text('₹${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: risk / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Avatar Widget (AppBar button) ────────────────────
class _ProfileAvatar extends StatelessWidget {
  final User? user;
  const _ProfileAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoURL;
    final name     = user?.displayName ?? user?.email ?? 'U';

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF4CAF50), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withOpacity(0.25),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
      child: ClipOval(
        child: photoUrl != null
            ? Image.network(photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(name))
            : _fallback(name),
      ),
    );
  }

  Widget _fallback(String name) {
    return Container(
      color: const Color(0xFF2E4A2E),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(
              color: Color(0xFF4CAF50),
              fontSize: 15,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}