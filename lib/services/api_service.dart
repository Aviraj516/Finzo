import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 🔁 Your FastAPI server IP — keep this running on your Mac
static const String baseUrl = "http://172.22.204.246:8000";  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ─────────────────────────────────────────
  // SETUP INCOME
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> setupIncome(double income) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/setup-income?income=$income'),
              headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // ADD EXPENSE
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> addExpense(
      String category, double amount) async {
    try {
      final res = await http
          .post(
              Uri.parse(
                  '$baseUrl/add-expense?category=$category&amount=$amount'),
              headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // SMS EXPENSE DETECTION
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> smsExpense(
      double amount, String merchant) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/sms-expense'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'amount': amount.toString(), 'merchant': merchant},
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // CREATE GOAL
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> createGoal(
      String name, double target) async {
    try {
      final res = await http
          .post(
              Uri.parse(
                  '$baseUrl/create-goal?goal_name=${Uri.encodeComponent(name)}&target_amount=$target'),
              headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // ADD SAVING
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> addSaving(
      String goalName, double amount) async {
    try {
      final res = await http
          .post(
              Uri.parse(
                  '$baseUrl/add-saving?goal_name=${Uri.encodeComponent(goalName)}&amount=$amount'),
              headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // FIX #12: GET GOALS — loads all goals from backend
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> getGoals() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/get-goals'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(res.body);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ─────────────────────────────────────────
  // FIX #13/#14: GET DASHBOARD — pure JSON, no HTML parsing
  // ─────────────────────────────────────────
  static Future<Map<String, dynamic>> getDashboardData() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/dashboard'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return {'error': 'Server error ${res.statusCode}'};
      }

      final data = jsonDecode(res.body);

      // Normalize types so Flutter doesn't crash on int vs double
      if (data['error'] != null) return data;

      return {
        'error':             null,
        'income':            (data['income']          ?? 0).toDouble(),
        'totalSpent':        (data['totalSpent']       ?? 0).toDouble(),
        'remainingBudget':   (data['remainingBudget']  ?? 0).toDouble(),
        'safeDailySpend':    (data['safeDailySpend']   ?? 0).toDouble(),
        'aiPrediction':       data['aiPrediction']     ?? '',
        'overspendingAlert':  data['overspendingAlert'] ?? '',
        'xp':                (data['xp']               ?? 0).toInt(),
        'streak':            (data['streak']            ?? 0).toInt(),
        'categorySpent': _toDoubleMap(data['categorySpent']),
        'categoryRisk':  _toDoubleMap(data['categoryRisk']),
        'categoryBudget': _toDoubleMap(data['categoryBudget']),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static Map<String, double> _toDoubleMap(dynamic raw) {
    if (raw == null) return {};
    final map = raw as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v ?? 0).toDouble()));
  }
}