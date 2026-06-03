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
      // Fetch last 100 SMS so we have enough to find 10 payment messages
      final List<SmsMessage> messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 100,
      );

      debugPrint('SmsService: 📬 Found ${messages.length} inbox messages');

      int found = 0;
      for (final msg in messages) {
        // Stop once we have exactly 10 payment transactions
        if (found >= 10) break;

        final body = msg.body ?? '';
        debugPrint('SmsService: checking → $body');

        if (_isTransaction(body)) {
          final data = _extractTransaction(body);
          if (data != null) {
            final amount   = double.tryParse(data['amount']!) ?? 0;
            final merchant = data['merchant']!;
            if (amount > 0) {
              debugPrint('SmsService: ✅ Transaction $found/10 → $merchant ₹$amount');
              onTransaction?.call(merchant, amount);
              await sendToBackend(data['amount']!, merchant);
              found++;
            }
          }
        }
      }

      debugPrint('SmsService: ✅ Parsed $found payment transactions from inbox');
    } catch (e) {
      debugPrint('SmsService._readInboxSms error: $e');
    }
  }

  // ── Strict payment SMS detector — ALL rules must pass ───
  //
  // Rule 1 — Must have a money amount pattern
  //   ₹500 | Rs.1,200 | INR 450 | Rs 99.00
  //
  // Rule 2 — Must have a debit/payment action keyword
  //   debited | paid | sent | withdrawn | purchase | spent
  //   (NOT just "payment" or "credited" alone — too noisy)
  //
  // Rule 3 — Must come from a known bank/payment sender
  //   OR contain a UPI reference / transaction ID pattern
  //
  // Rule 4 — Must NOT be an OTP / promo / alert-only SMS
  //   (hard-reject if it contains OTP/promo signals)
  //
  bool _isTransaction(String sms) {
    final lower = sms.toLowerCase();

    // ── Rule 4 first: hard-reject non-payment SMS ─────────
    // OTP messages
    if (RegExp(r'\b(otp|one.?time.?pass|verification code|do not share)\b',
        caseSensitive: false).hasMatch(sms)) return false;
    // Purely promotional / offer messages
    if (RegExp(r'\b(offer|discount|cashback earn|win|congratulations|promo|voucher|coupon|reward points)\b',
        caseSensitive: false).hasMatch(sms) &&
        !RegExp(r'\b(debited|withdrawn|paid|sent|spent|purchase)\b',
            caseSensitive: false).hasMatch(sms)) return false;
    // Low-balance / account alerts that are NOT transactions
    if (RegExp(r'\b(low balance|minimum balance|kyc|nominee|update your|linked|registered)\b',
        caseSensitive: false).hasMatch(sms) &&
        !RegExp(r'\b(debited|withdrawn|paid|sent|spent|purchase)\b',
            caseSensitive: false).hasMatch(sms)) return false;

    // ── Rule 1: must contain a real rupee amount ──────────
    final hasAmount = RegExp(
      r'(?:rs\.?\s*|inr\s*|₹\s*)[0-9,]+(?:\.[0-9]{1,2})?',
      caseSensitive: false,
    ).hasMatch(sms);
    if (!hasAmount) return false;

    // ── Rule 2: must have a debit/payment action word ─────
    // "credited" alone is skipped — it's income, not expense
    final hasDebitAction = RegExp(
      r'\b(debited|debit|withdrawn|withdrawal|paid|sent|spent|purchase|purchased|deducted)\b',
      caseSensitive: false,
    ).hasMatch(sms);
    if (!hasDebitAction) return false;

    // ── Rule 3: must have bank/UPI signal ─────────────────
    // Either a known bank sender pattern OR a UPI/txn ref
    final hasBankSignal = RegExp(
      r'\b(upi|imps|neft|rtgs|a/c|acct|account|hdfc|sbi|icici|axis|kotak|paytm|phonepe|gpay|amazon\s*pay|idfc|yes\s*bank|pnb|bob|canara|union\s*bank|indusind|federal|rbl)\b',
      caseSensitive: false,
    ).hasMatch(sms);

    final hasTxnRef = RegExp(
      r'\b(ref|txn|transaction\s*id|utr|order\s*id)[:\s#]*[a-z0-9]{6,}\b',
      caseSensitive: false,
    ).hasMatch(sms);

    if (!hasBankSignal && !hasTxnRef) return false;

    // ── All rules passed ──────────────────────────────────
    return true;
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
