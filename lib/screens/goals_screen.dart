import 'package:flutter/material.dart';
import '../services/api_service.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  // Local goals mirror (backend is source of truth on save)
  List<Map<String, dynamic>> goals = [];
  bool isLoading = false;

  // ── Create Goal ─────────────────────────────────────────
  void _showCreateGoalDialog() {
    final nameCtrl = TextEditingController();
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
              final name = nameCtrl.text.trim();
              final target = double.tryParse(targetCtrl.text);
              if (name.isEmpty || target == null) return;
              Navigator.pop(context);

              setState(() => isLoading = true);

              // 🔗 BACKEND CALL: POST /create-goal
              final result = await ApiService.createGoal(name, target);

              setState(() {
                isLoading = false;
                if (result['error'] == null) {
                  goals.add({'name': name, 'target': target, 'saved': 0.0});
                }
              });

              _snack(
                result['error'] != null
                    ? '❌ ${result['error']}'
                    : '🎯 Goal "$name" created!',
                result['error'] != null ? Colors.red : const Color(0xFF4CAF50),
              );
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Add Saving to Goal ──────────────────────────────────
  void _showAddSavingDialog(int index) {
    final amountCtrl = TextEditingController();
    final goal = goals[index];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('💚 Add to "${goal['name']}"'),
        content:
            _inputField(amountCtrl, 'Amount to Save', 'e.g. 5000', '₹ '),
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

              // 🔗 BACKEND CALL: POST /add-saving
              final result =
                  await ApiService.addSaving(goal['name'] as String, amt);

              setState(() {
                isLoading = false;
                if (result['error'] == null) {
                  goals[index]['saved'] =
                      (goals[index]['saved'] as double) + amt;
                }
              });

              _snack(
                result['error'] != null
                    ? '❌ ${result['error']}'
                    : '✅ ₹$amt saved! Progress: ${result['progress_percent']}%',
                result['error'] != null ? Colors.red : const Color(0xFF4CAF50),
              );
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
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

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGoalDialog,
        backgroundColor: const Color(0xFF4CAF50),
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('New Goal', style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : goals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🎯', style: TextStyle(fontSize: 60)),
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
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: goals.length,
                  itemBuilder: (_, i) => _goalCard(i),
                ),
    );
  }

  Widget _goalCard(int index) {
    final goal = goals[index];
    final saved = (goal['saved'] as double);
    final target = (goal['target'] as double);
    final progress = (saved / target).clamp(0.0, 1.0);
    final pct = (progress * 100).toStringAsFixed(1);
    final remaining = target - saved;

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
              Text(goal['name'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Text('$pct%',
                  style: TextStyle(
                      color: progressColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('₹${saved.toStringAsFixed(0)} / ₹${target.toStringAsFixed(0)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
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
