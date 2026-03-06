import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> goals = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  @override
  bool get wantKeepAlive => true;

  // ── Safe number parser (handles String / int / double / null) ──
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // ── Load Goals ────────────────────────────────────────────
  Future<void> _loadGoals() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final result = await ApiService.getGoals();

      if (!mounted) return;

      if (result['error'] != null) {
        _snack('❌ ${result['error']}', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final rawGoals = result['goals'];

      // Backend might return null or a non-list — guard it
      if (rawGoals == null || rawGoals is! List) {
        setState(() {
          isLoading = false;
          goals = [];
        });
        return;
      }

      setState(() {
        isLoading = false;
        goals = rawGoals.map<Map<String, dynamic>>((g) {
          final map = g as Map<String, dynamic>;
          return {
            'name':   (map['name']   ?? '').toString(),
            'target': _toDouble(map['target']),
            'saved':  _toDouble(map['saved']),
          };
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _snack('❌ Failed to load goals: ${_friendlyError(e)}', Colors.red);
    }
  }

  // ── Create Goal ───────────────────────────────────────────
  void _showCreateGoalDialog() {
    final nameCtrl   = TextEditingController();
    final targetCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🎯 Create New Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inputField(nameCtrl, 'Goal Name', 'e.g. New Laptop', null),
            const SizedBox(height: 12),
            _inputField(targetCtrl, 'Target Amount', 'e.g. 60000', '₹ '),
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
              final name   = nameCtrl.text.trim();
              final target = double.tryParse(targetCtrl.text.trim());

              if (name.isEmpty) {
                _snack('⚠️ Please enter a goal name', Colors.orange);
                return;
              }
              if (target == null || target <= 0) {
                _snack('⚠️ Please enter a valid target amount', Colors.orange);
                return;
              }

              Navigator.pop(context);
              setState(() => isLoading = true);

              try {
                final result = await ApiService.createGoal(name, target);

                if (!mounted) return;
                setState(() => isLoading = false);

                if (result['error'] != null) {
                  _snack('❌ ${result['error']}', Colors.red);
                  return;
                }

                // Use backend-returned values if present, otherwise use local
                setState(() {
                  goals.add({
                    'name':   (result['name']   ?? name).toString(),
                    'target': _toDouble(result['target'] ?? target),
                    'saved':  _toDouble(result['saved']  ?? 0),
                  });
                });

                _snack('🎯 Goal "$name" created!', const Color(0xFF4CAF50));
              } catch (e) {
                if (!mounted) return;
                setState(() => isLoading = false);
                _snack('❌ Could not create goal: ${_friendlyError(e)}',
                    Colors.red);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Add Saving ────────────────────────────────────────────
  void _showAddSavingDialog(int index) {
    final amountCtrl = TextEditingController();
    final goal       = goals[index];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('💚 Add to "${goal['name']}"'),
        content: _inputField(amountCtrl, 'Amount to Save', 'e.g. 5000', '₹ '),
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
              final amt = double.tryParse(amountCtrl.text.trim());

              if (amt == null || amt <= 0) {
                _snack('⚠️ Please enter a valid amount', Colors.orange);
                return;
              }

              Navigator.pop(context);
              setState(() => isLoading = true);

              try {
                final result = await ApiService.addSaving(
                    goal['name'] as String, amt);

                if (!mounted) return;
                setState(() => isLoading = false);

                if (result['error'] != null) {
                  _snack('❌ ${result['error']}', Colors.red);
                  return;
                }

                // Update saved amount — use backend value if returned,
                // otherwise add locally to avoid a reload round-trip.
                setState(() {
                  final newSaved = result.containsKey('saved')
                      ? _toDouble(result['saved'])
                      : _toDouble(goals[index]['saved']) + amt;
                  goals[index] = {
                    ...goals[index],
                    'saved': newSaved,
                  };
                });

                final pct = result['progress_percent']?.toString() ?? '';
                _snack(
                  '✅ ₹$amt saved!${pct.isNotEmpty ? ' Progress: $pct%' : ''}',
                  const Color(0xFF4CAF50),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => isLoading = false);
                _snack('❌ Could not save: ${_friendlyError(e)}', Colors.red);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Friendly error messages ───────────────────────────────
  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') || msg.contains('network')) {
      return 'No internet connection';
    }
    if (msg.contains('timeout') || msg.contains('timeoutexception')) {
      return 'Request timed out — check your server';
    }
    if (msg.contains('handshake') || msg.contains('certificate')) {
      return 'SSL/TLS error — check server certificate';
    }
    if (msg.contains('formatexception') || msg.contains('json')) {
      return 'Server returned unexpected data';
    }
    if (msg.contains('type') && msg.contains('is not a subtype')) {
      return 'Data format mismatch — check API response';
    }
    // Return first 80 chars so the snackbar doesn't overflow
    return e.toString().length > 80
        ? '${e.toString().substring(0, 80)}…'
        : e.toString();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF0EFE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0EFE9),
        elevation: 0,
        title: const Text('🎯 Savings Goals',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.black)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black54),
            onPressed: _loadGoals,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGoalDialog,
        backgroundColor: const Color(0xFF4CAF50),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Goal', style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : RefreshIndicator(
              color: const Color(0xFF4CAF50),
              onRefresh: _loadGoals,
              child: goals.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🎯',
                                  style: TextStyle(fontSize: 60)),
                              const SizedBox(height: 16),
                              Text('No goals yet!',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[600])),
                              const SizedBox(height: 8),
                              Text('Tap + to create your first savings goal',
                                  style: TextStyle(color: Colors.grey[400])),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: goals.length,
                      itemBuilder: (_, i) => _goalCard(i),
                    ),
            ),
    );
  }

  Widget _goalCard(int index) {
    final goal          = goals[index];
    final double saved  = _toDouble(goal['saved']);
    final double target = _toDouble(goal['target']);
    final double progress =
        target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
    final pct       = (progress * 100).toStringAsFixed(1);
    final remaining = (target - saved).clamp(0.0, double.infinity);

    Color progressColor;
    if (progress < 0.4) {
      progressColor = Colors.orange;
    } else if (progress < 0.8) {
      progressColor = Colors.blue;
    } else {
      progressColor = const Color(0xFF4CAF50);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (goal['name'] ?? '').toString(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text('$pct%',
                  style: TextStyle(
                      color: progressColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '₹${saved.toStringAsFixed(0)} / ₹${target.toStringAsFixed(0)}',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('₹${remaining.toStringAsFixed(0)} remaining',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: () => _showAddSavingDialog(index),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('+ Add Saving',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, String hint,
      String? prefix) {
    return TextField(
      controller: ctrl,
      keyboardType:
          prefix != null ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}