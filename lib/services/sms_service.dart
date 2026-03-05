import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class SmsService {
  final SmsQuery _query = SmsQuery();

  // ✅ onTransaction callback added
  Future<void> startListening({
    void Function(String merchant, double amount)? onTransaction,
  }) async {
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      debugPrint('SMS permission denied');
      return;
    }

    await _processRecentSms(onTransaction: onTransaction);
  }

  Future<void> _processRecentSms({
    void Function(String merchant, double amount)? onTransaction,
  }) async {
    try {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 100, // ✅ fetch 100 to find 20 transactions
      );

      int found = 0;

      for (final message in messages) {
        if (found >= 20) break; // ✅ max 20 transactions

        final body = message.body ?? '';
        debugPrint('SMS: $body');

        if (_isTransaction(body)) {
          final data = _extractTransaction(body);
          if (data != null) {
            final double amount = double.tryParse(data['amount']!) ?? 0;
            final String merchant = data['merchant']!;

            // ✅ Fire callback so HomeScreen/DashboardScreen can update UI
            if (onTransaction != null) {
              onTransaction(merchant, amount);
            }

            // ✅ Send to FastAPI backend
            await sendToBackend(data['amount']!, merchant);

            found++;
          }
        }
      }
    } catch (e) {
      debugPrint('SmsService Error: $e');
    }
  }

  bool _isTransaction(String sms) {
    final lower = sms.toLowerCase();
    return lower.contains('rs') ||
        lower.contains('debited') ||
        lower.contains('sent') ||
        lower.contains('paid') ||
        lower.contains('upi');
  }

  Map<String, String>? _extractTransaction(String sms) {
    final amountRegex = RegExp(r'rs\.?\s?(\d+)', caseSensitive: false);
    final amountMatch = amountRegex.firstMatch(sms);
    if (amountMatch == null) return null;

    final amount = amountMatch.group(1)!;

    final merchantRegex =
        RegExp(r'to\s([a-zA-Z\s]+)', caseSensitive: false);
    final merchantMatch = merchantRegex.firstMatch(sms);
    final merchant = merchantMatch != null
        ? merchantMatch.group(1)!.trim()
        : 'Unknown';

    return {
      'amount': amount,
      'merchant': merchant,
    };
  }

  Future<void> sendToBackend(String amount, String merchant) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.7:8000/sms-expense'), // ✅ your IP
        body: {
          'amount': amount,
          'merchant': merchant,
        },
      );
      debugPrint('sendToBackend response: ${response.body}');
    } catch (e) {
      debugPrint('sendToBackend Error: $e');
    }
  }
}