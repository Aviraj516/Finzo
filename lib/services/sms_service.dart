import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

// ─────────────────────────────────────────────────────────────
// SmsService — uses flutter_sms_inbox (matches your pubspec)
// ─────────────────────────────────────────────────────────────
class SmsService {
  static const String _baseUrl = 'http://192.168.31.119:8000';
  final SmsQuery _query = SmsQuery();

  Future<void> startListening({
    void Function(String merchant, double amount)? onTransaction,
  }) async {
    try {
      // ── Step 1: Request SMS permission at runtime ────────
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        debugPrint('SmsService: ❌ SMS permission denied');
        return;
      }
      debugPrint('SmsService: ✅ SMS permission granted');

      // ── Step 2: Read inbox SMS ───────────────────────────
      await _readInboxSms(onTransaction: onTransaction);

    } catch (e) {
      debugPrint('SmsService: not available on this device → $e');
    }
  }

  // ── Read SMS from inbox ──────────────────────────────────
  Future<void> _readInboxSms({
    void Function(String merchant, double amount)? onTransaction,
  }) async {
    try {
      // Get all inbox messages
      final List<SmsMessage> messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 50, // fetch last 50 SMS
      );

      debugPrint('SmsService: 📬 Found ${messages.length} inbox messages');

      int found = 0;
      for (final msg in messages) {
        if (found >= 20) break;
        final body = msg.body ?? '';
        debugPrint('SmsService: checking → $body');

        if (_isTransaction(body)) {
          final data = _extractTransaction(body);
          if (data != null) {
            final amount   = double.tryParse(data['amount']!) ?? 0;
            final merchant = data['merchant']!;
            if (amount > 0) {
              debugPrint('SmsService: ✅ Transaction → $merchant ₹$amount');
              onTransaction?.call(merchant, amount);
              await sendToBackend(data['amount']!, merchant);
              found++;
            }
          }
        }
      }

      debugPrint('SmsService: ✅ Parsed $found transactions from inbox');
    } catch (e) {
      debugPrint('SmsService._readInboxSms error: $e');
    }
  }

  // ── Detect if SMS looks like a bank transaction ──────────
  bool _isTransaction(String sms) {
    final lower = sms.toLowerCase();
    return lower.contains('rs')          ||
           lower.contains('inr')         ||
           lower.contains('₹')           ||
           lower.contains('debited')     ||
           lower.contains('credited')    ||
           lower.contains('sent')        ||
           lower.contains('paid')        ||
           lower.contains('payment')     ||
           lower.contains('upi')         ||
           lower.contains('transaction') ||
           lower.contains('withdrawn')   ||
           lower.contains('purchase');
  }

  // ── Extract amount + merchant from SMS body ──────────────
  Map<String, String>? _extractTransaction(String sms) {

    // ── Amount extraction ────────────────────────────────
    // Handles: Rs.500 | Rs 1,234.50 | INR 500 | ₹500 | debited 500
    final amountPatterns = [
      RegExp(r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(r'(?:debited|paid|sent|spent|payment of|amount of)\s+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|₹)',
          caseSensitive: false),
    ];

    String? amount;
    for (final pattern in amountPatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        final raw = match.group(1)?.replaceAll(',', '') ?? '';
        if (double.tryParse(raw) != null) {
          amount = raw;
          break;
        }
      }
    }
    if (amount == null) return null;

    // ── Merchant extraction ──────────────────────────────
    // Handles: "to Zomato" | "at Amazon" | "@ Swiggy" | "merchant: HDFC"
    final merchantPatterns = [
      RegExp(
        r'(?:to|at|@|for)\s+([A-Za-z0-9][A-Za-z0-9\s\-&\.]{1,25}?)(?:\s+on\b|\s+via\b|\s+ref\b|\s+upi\b|\s+vpa\b|\s+using\b|[,.\n]|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:merchant|shop|store)[:\s]+([A-Za-z0-9][A-Za-z0-9\s\-&\.]{1,25}?)(?:[,.\n]|$)',
        caseSensitive: false,
      ),
    ];

    String merchant = 'Unknown';
    for (final pattern in merchantPatterns) {
      final match = pattern.firstMatch(sms);
      if (match != null) {
        final name = match.group(1)?.trim() ?? '';
        if (name.length > 2) {
          merchant = _cleanMerchant(name);
          break;
        }
      }
    }

    return {'amount': amount, 'merchant': merchant};
  }

  // ── Clean up merchant name ───────────────────────────────
  String _cleanMerchant(String raw) {
    const noiseWords = ['ltd', 'pvt', 'private', 'limited', 'india', 'online'];
    var name = raw.trim();
    for (final word in noiseWords) {
      name = name
          .replaceAll(RegExp('\\b$word\\b', caseSensitive: false), '')
          .trim();
    }
    // Title case
    return name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  // ── Send to FastAPI backend ──────────────────────────────
  Future<void> sendToBackend(String amount, String merchant) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/sms-expense'),
            body: {'amount': amount, 'merchant': merchant},
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('SmsService.sendToBackend: ${response.statusCode} ${response.body}');
    } catch (e) {
      debugPrint('SmsService.sendToBackend error: $e');
    }
  }
}