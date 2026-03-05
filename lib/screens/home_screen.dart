import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';

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

  // SMS + Transactions
  final SmsService _smsService = SmsService();
  final List<_Transaction> _transactions = [];

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

    // 🔔 Start SMS listener — auto-detects bank transactions
    _smsService.startListening(
      onTransaction: (merchant, amount) {
        setState(() {
          _transactions.insert(
            0,
            _Transaction(merchant: merchant, amount: amount, time: DateTime.now()),
          );
          totalSpent += amount;
          _updatePlant();
        });
        _showSnack(
          '💳 New transaction: $merchant ₹$amount',
          const Color(0xFF4CAF50),
        );
      },
    );
  }

  @override
  void dispose() {
    _plantAnim.dispose();
    super.dispose();
  }

  // ── Plant Logic ────────────────────────────────────────
  void _updatePlant() {
    if (xp < 30) {
      plantStage = '🌱';
      plantLabel = 'Seed';
    } else if (xp < 70) {
      plantStage = '🌿';
      plantLabel = 'Sprout';
    } else if (xp < 120) {
      plantStage = '🌳';
      plantLabel = 'Young Tree';
    } else if (xp < 200) {
      plantStage = '🌲';
      plantLabel = 'Strong Tree';
    } else {
      plantStage = '🌴';
      plantLabel = 'Money Tree';
    }
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
                  _plantAnim
                    ..reset()
                    ..forward();
                }
              });

              _showSnack(
                result['error'] != null
                    ? 'Error: ${result['error']}'
                    : 'Income set to ₹$val',
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
                    totalSpent += amt;
                    xp = result['xp'] ?? xp;
                    _updatePlant();
                    _plantAnim
                      ..reset()
                      ..forward();
                  }
                });

                _showSnack(
                  result['error'] != null
                      ? 'Error: ${result['error']}'
                      : '₹$amt added | Risk: ${result['risk']}% | XP: ${result['xp']}',
                  result['error'] != null
                      ? Colors.red
                      : const Color(0xFF4CAF50),
                );
              },
              child: const Text('Add', style: TextStyle(color: Colors.white)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final balance = income - totalSpent;
    final growthPercent = ((xp / 200) * 100).clamp(0, 100);

    return Scaffold(
      backgroundColor: const Color(0xFFF0EFE9),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ── Header ──────────────────────────────
                    Row(
                      children: [
                        const Text(
                          'Finzo',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.eco,
                            color: Color(0xFF4CAF50), size: 26),
                        const Spacer(),
                        CircleAvatar(
                          backgroundColor: const Color(0xFF4CAF50),
                          child:
                              const Icon(Icons.person, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── User greeting ────────────────────────
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              const Color(0xFF4CAF50).withOpacity(0.15),
                          child: const Icon(Icons.spa,
                              color: Color(0xFF4CAF50), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Hey, Avi!',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Row(
                              children: [
                                const Icon(Icons.local_fire_department,
                                    color: Colors.orange, size: 14),
                                const SizedBox(width: 4),
                                Text('$plantLabel · Streak: $streak',
                                    style: const TextStyle(
                                        color: Color(0xFF4CAF50),
                                        fontSize: 12)),
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

                    // ── Money Plant Card ─────────────────────
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
                        children: [
                          // Title row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.yard, color: Colors.grey, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'YOUR MONEY PLANT',
                                style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1.5,
                                    color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF4CAF50).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF4CAF50), width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.eco,
                                    color: Color(0xFF4CAF50), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  plantLabel,
                                  style: const TextStyle(
                                      color: Color(0xFF4CAF50),
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Animated plant emoji (kept large — looks great at 100px)
                          ScaleTransition(
                            scale: _scaleAnim,
                            child: Text(plantStage,
                                style: const TextStyle(fontSize: 100)),
                          ),
                          const SizedBox(height: 16),

                          // Growth progress bar
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F0),
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
                                    backgroundColor: Colors.grey[200],
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Color(0xFF4CAF50)),
                                    minHeight: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Balance Card ─────────────────────────
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
                          const Text('TOTAL BALANCE',
                              style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                  color: Colors.grey)),
                          const SizedBox(height: 6),
                          Text(
                            '₹${balance.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 34, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _balanceTile('Income', income, Colors.green,
                                  Icons.arrow_downward),
                              const SizedBox(width: 20),
                              _balanceTile('Expenses', totalSpent, Colors.pink,
                                  Icons.arrow_upward),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Recent Transactions Card ─────────────
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
                              const Text(
                                'Recent Transactions',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50)
                                      .withOpacity(0.1),
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

                          // Transaction list or empty state
                          _transactions.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 20),
                                    child: Column(
                                      children: [
                                        Icon(Icons.sms_outlined,
                                            size: 40,
                                            color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No transactions yet\nSMS listener is active',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: _transactions.length > 5
                                      ? 5
                                      : _transactions.length,
                                  separatorBuilder: (_, __) => Divider(
                                      color: Colors.grey[100], height: 1),
                                  itemBuilder: (context, index) {
                                    final tx = _transactions[index];
                                    return _transactionTile(tx);
                                  },
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Helper Widgets ─────────────────────────────────────

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

  Widget _balanceTile(
      String label, double amount, Color color, IconData icon) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text('₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _transactionTile(_Transaction tx) {
    // Pick icon + color based on merchant name
    IconData icon = Icons.shopping_bag_outlined;
    Color iconColor = const Color(0xFF5C6BC0);
    Color iconBg = const Color(0xFFE8EAF6);

    final m = tx.merchant.toLowerCase();
    if (m.contains('amazon') || m.contains('flipkart') || m.contains('shop')) {
      icon = Icons.shopping_cart_outlined;
      iconColor = const Color(0xFF5C6BC0);
      iconBg = const Color(0xFFE8EAF6);
    } else if (m.contains('uber') || m.contains('ola') || m.contains('travel')) {
      icon = Icons.directions_car_outlined;
      iconColor = const Color(0xFF212121);
      iconBg = const Color(0xFFF5F5F5);
    } else if (m.contains('zomato') || m.contains('swiggy') || m.contains('food')) {
      icon = Icons.fastfood_outlined;
      iconColor = const Color(0xFFE64A19);
      iconBg = const Color(0xFFFBE9E7);
    } else if (m.contains('starbucks') || m.contains('cafe') || m.contains('coffee')) {
      icon = Icons.local_cafe_outlined;
      iconColor = const Color(0xFF5D4037);
      iconBg = const Color(0xFFEFEBE9);
    } else if (m.contains('paytm') || m.contains('gpay') || m.contains('phonepe') || m.contains('upi')) {
      icon = Icons.account_balance_wallet_outlined;
      iconColor = const Color(0xFF4CAF50);
      iconBg = const Color(0xFFE8F5E9);
    }

    // Format relative time
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
                Text(
                  tx.merchant,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(timeStr,
                    style: TextStyle(fontSize: 11, color: Colors.grey[400])),
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