import 'package:flutter/material.dart';
import '../services/api_service.dart';

class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen>
    with AutomaticKeepAliveClientMixin {
  int streak  = 0;
  int xp      = 0;
  bool isLoading = false;

  // FIX #9: today is computed from actual current day, not hardcoded
  late List<Map<String, dynamic>> weekDays;

  @override
  void initState() {
    super.initState();
    _buildWeekDays(); // build with real today
    _loadXp();        // FIX #10: fetch xp from backend
  }

  @override
  bool get wantKeepAlive => true;

  // FIX #9: builds weekDays with correct today
  void _buildWeekDays() {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    // DateTime.weekday: 1=Monday … 7=Sunday
    final todayIndex = DateTime.now().weekday - 1;

    weekDays = List.generate(7, (i) => {
      'day':    days[i],
      'logged': false,
      'today':  i == todayIndex,
    });
  }

  // FIX #10: load xp + streak from backend
  Future<void> _loadXp() async {
    if (!mounted) return;
    final data = await ApiService.getDashboardData();
    if (!mounted) return;
    if (data['error'] == null) {
      setState(() {
        xp     = ((data['xp']     ?? 0) as num).toInt();
        streak = ((data['streak'] ?? 0) as num).toInt();
        // Mark today as logged if streak > 0
        if (streak > 0) {
          final todayIdx = weekDays.indexWhere((d) => d['today'] == true);
          if (todayIdx >= 0) weekDays[todayIdx]['logged'] = true;
        }
      });
    }
  }

  // ── Log Today ─────────────────────────────────────────────
  void _logToday() {
    final amountCtrl = TextEditingController();
    String selectedCategory = 'Food';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('💧 Water Your Plant!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Log an expense to earn XP & grow your streak!',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
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
                items: ['Food', 'Shopping', 'Travel']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) =>
                    setD(() => selectedCategory = v ?? 'Food'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: 'Amount spent',
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
                    xp     = ((result['xp']     ?? xp) as num).toInt();
                    streak = ((result['streak'] ?? streak) as num).toInt();
                    // Mark today as logged
                    final todayIdx =
                        weekDays.indexWhere((d) => d['today'] == true);
                    if (todayIdx >= 0) {
                      weekDays[todayIdx]['logged'] = true;
                    }
                  }
                });

                _snack(
                  result['error'] != null
                      ? '❌ ${result['error']}'
                      : '⚡ +${result['xp'] ?? 0} XP! Plant watered 💧',
                  result['error'] != null
                      ? Colors.red
                      : const Color(0xFF4CAF50),
                );
              },
              child: const Text('Log Now! ⚡',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF0EFE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0EFE9),
        elevation: 0,
        title: const Text('Finzo 🌿',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: Colors.black)),
        actions: [
          CircleAvatar(
            backgroundColor: const Color(0xFF4CAF50),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // ── Quick Actions Row ──────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _actionChip('💰', 'Receive', const Color(0xFFE8F5E9)),
                      _actionChip('💸', 'Pay',     const Color(0xFFEDE7F6)),
                      _actionChip('📈', 'Invest',  const Color(0xFFFFF8E1)),
                      _actionChip('🎯', 'Goals',   const Color(0xFFFCE4EC)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Water Plant Challenge ──────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF4CAF50), width: 1.5),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                              child: Text('🎯',
                                  style: TextStyle(fontSize: 22))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Daily Challenge',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              Text('Log today\'s expense to water your plant!',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _logToday,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Log',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Streak Banner ──────────────────────────
                  GestureDetector(
                    onTap: _logToday,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C35C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                                child: Text('🔥',
                                    style: TextStyle(fontSize: 24))),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$streak-day Streak! Keep going!',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const Text('Keep it up — 8 days to top 10%!',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('⚡ $xp XP',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Weekly Streak Calendar ─────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 8),
                            Text('$streak-Day Streak!',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...weekDays.map((d) => _dayRow(d)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _dayRow(Map<String, dynamic> day) {
    final isToday  = day['today']  == true;
    final isLogged = day['logged'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isToday
            ? const Color(0xFF2A2A1E)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: isToday
            ? Border.all(color: const Color(0xFFFF9800), width: 1.5)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day['day'] as String,
                    style: TextStyle(
                        color: isToday ? Colors.white : Colors.grey[400],
                        fontWeight: FontWeight.w600)),
                Text(
                  isLogged
                      ? 'Logged ✅'
                      : isToday
                          ? 'Today — Log now!'
                          : 'Not logged',
                  style: TextStyle(
                    fontSize: 12,
                    color: isLogged
                        ? const Color(0xFF4CAF50)
                        : isToday
                            ? const Color(0xFFFF9800)
                            : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          isToday && !isLogged
              ? GestureDetector(
                  onTap: _logToday,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFFF9800), width: 1.5),
                    ),
                    child: const Center(
                        child: Text('🔥',
                            style: TextStyle(fontSize: 16))),
                  ),
                )
              : Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: isLogged
                        ? const Color(0xFF4CAF50).withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isLogged
                            ? const Color(0xFF4CAF50)
                            : Colors.grey.withOpacity(0.3),
                        width: 1.5),
                  ),
                  child: Center(
                      child: Icon(
                    isLogged ? Icons.check : Icons.close,
                    size: 16,
                    color: isLogged
                        ? const Color(0xFF4CAF50)
                        : Colors.grey,
                  )),
                ),
        ],
      ),
    );
  }

  Widget _actionChip(String emoji, String label, Color bg) {
    return Column(
      children: [
        Container(
          width: 68, height: 68,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(18)),
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
    );
  }
}