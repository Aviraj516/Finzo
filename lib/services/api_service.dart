import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 🔁 Change this to your FastAPI server IP
  static const String baseUrl = 'http://192.168.31.119:8000';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ─────────────────────────────────────────
  // SETUP INCOME  →  POST /setup-income
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> setupIncome(double income) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/setup-income?income=$income'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // ADD EXPENSE  →  POST /add-expense
  // Returns: { risk, xp }
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> addExpense(
      String category, double amount) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/add-expense?category=$category&amount=$amount'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // SMS EXPENSE DETECTION  →  POST /sms-expense
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> smsExpense(
      double amount, String merchant) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/sms-expense'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'amount': amount.toString(),
              'merchant': merchant,
            },
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // CREATE GOAL  →  POST /create-goal
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> createGoal(
      String name, double target) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/create-goal?goal_name=$name&target_amount=$target'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // ADD SAVING  →  POST /add-saving
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> addSaving(
      String goalName, double amount) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/add-saving?goal_name=$goalName&amount=$amount'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // GET DASHBOARD DATA  →  GET /ui (parsed)
  // Returns all fields Flutter needs
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> getDashboardData() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/ui'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return {'error': 'Server error ${res.statusCode}'};
      return _parseHtmlData(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Parses the FastAPI /ui HTML into a full Flutter-friendly map
  static Map<String, dynamic> _parseHtmlData(String html) {
    // Income not set yet
    if (html.contains('setup income') || html.contains('Setup income')) {
      return {'error': 'income_not_set'};
    }

    // ── Helper: extract number after label ──
    double extractNum(String label) {
      final pattern = RegExp('$label[^₹]*₹([\\d.]+)', dotAll: true);
      final match = pattern.firstMatch(html);
      return double.tryParse(match?.group(1) ?? '0') ?? 0;
    }

    // ── Core values ──
    final totalSpent = extractNum('Total Spent');
    final remainingBudget = extractNum('Remaining Budget');
    final safeDailySpend = extractNum('Safe Daily Spend');

    // ── AI Prediction ──
    String aiPrediction = '—';
    final predMatch = RegExp(
            r'<h3>AI Spending Prediction<\/h3>\s*<p>([^<]+)<\/p>')
        .firstMatch(html);
    if (predMatch != null) {
      aiPrediction = predMatch.group(1)?.trim() ?? '—';
    }

    // ── Category spent amounts ──
    Map<String, double> categorySpent = {};
    Map<String, double> categoryRisk = {};

    for (final cat in ['Food', 'Shopping', 'Travel']) {
      // Matches: <strong>Food</strong> — ₹200 / ₹...
      final catMatch = RegExp(
              '<strong>$cat<\\/strong> — ₹([\\d.]+) \\/ ₹[\\d.]+<br>\\s*'
              "<span style='color:\\w+;'>([\\d.]+)%")
          .firstMatch(html);
      if (catMatch != null) {
        categorySpent[cat] = double.tryParse(catMatch.group(1) ?? '0') ?? 0;
        categoryRisk[cat] = double.tryParse(catMatch.group(2) ?? '0') ?? 0;
      } else {
        categorySpent[cat] = 0;
        categoryRisk[cat] = 0;
      }
    }

    return {
      'totalSpent': totalSpent,
      'remainingBudget': remainingBudget,
      'safeDailySpend': safeDailySpend,
      'aiPrediction': aiPrediction,
      'categorySpent': categorySpent,
      'categoryRisk': categoryRisk,
    };
  }
}