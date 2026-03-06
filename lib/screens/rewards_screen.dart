import 'package:flutter/material.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  static const List<_RewardItem> _rewards = [
    _RewardItem(emoji: '💰', title: '₹10 Cashback', subtitle: '3 Day Tracking'),
    _RewardItem(emoji: '🎟️', title: '₹50 Voucher', subtitle: 'Save ₹500'),
    _RewardItem(emoji: '📦', title: 'Amazon ₹100', subtitle: 'XP > 100'),
    _RewardItem(emoji: '🏆', title: 'Plant Badge', subtitle: 'Reach Level 3'),
    _RewardItem(emoji: '💵', title: '₹25 Cashback', subtitle: '5 Day Streak'),
    _RewardItem(emoji: '⭐', title: 'Bonus XP', subtitle: 'Track Expenses'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3CAB57),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Text(
              'Rewards ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            Text('🎁', style: TextStyle(fontSize: 20)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: _rewards.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final reward = _rewards[index];
            return _RewardCard(item: reward);
          },
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final _RewardItem item;
  const _RewardCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardItem {
  final String emoji;
  final String title;
  final String subtitle;
  const _RewardItem(
      {required this.emoji, required this.title, required this.subtitle});
}