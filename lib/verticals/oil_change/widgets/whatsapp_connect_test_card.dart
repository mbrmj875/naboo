import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/whatsapp_failure_reason_ar.dart';

/// نتيجة طلب الإرسال من البوابة.
typedef ConnectTestSend = Future<({bool ok, String? key, String? messageAr})>
    Function(String phone);

/// حالة السجل: delivered أو read أو failed أو sent.
typedef ConnectTestStatus = Future<({String status, String error})?> Function(
  String key,
);

/// زر رسالة التجربة. لا يظهر النجاح إلا بعد تأكيد الوصول من واتساب.
class WhatsappConnectTestCard extends StatefulWidget {
  const WhatsappConnectTestCard({
    super.key,
    required this.send,
    required this.fetchStatus,
    this.pollInterval = const Duration(seconds: 5),
    this.maxPolls = 24,
  });

  final ConnectTestSend send;
  final ConnectTestStatus fetchStatus;
  final Duration pollInterval;
  final int maxPolls;

  @override
  State<WhatsappConnectTestCard> createState() =>
      _WhatsappConnectTestCardState();
}

class _WhatsappConnectTestCardState extends State<WhatsappConnectTestCard> {
  final _phone = TextEditingController();
  Timer? _timer;
  bool _busy = false;
  bool? _delivered;
  String? _message;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _delivered = null;
      _message = null;
    });
    final result = await widget.send(_phone.text.trim());
    if (!mounted) return;
    final key = result.key;
    if (!result.ok || key == null) {
      setState(() {
        _busy = false;
        _delivered = false;
        _message = result.messageAr ?? 'تعذّر إرسال رسالة التجربة.';
      });
      return;
    }
    setState(() => _message = 'أُرسلت رسالة التجربة، وننتظر تأكيد الوصول…');
    _poll(key);
  }

  void _poll(String key) {
    var polls = 0;
    var checking = false;
    _timer?.cancel();
    _timer = Timer.periodic(widget.pollInterval, (timer) async {
      if (checking) return;
      checking = true;
      polls += 1;
      final row = await widget.fetchStatus(key);
      checking = false;
      if (!mounted) {
        timer.cancel();
        return;
      }
      final status = row?.status ?? '';
      if (status == 'delivered' || status == 'read') {
        timer.cancel();
        setState(() {
          _busy = false;
          _delivered = true;
          _message = 'وصلت رسالة التجربة إلى رقمك.';
        });
      } else if (status == 'failed') {
        timer.cancel();
        setState(() {
          _busy = false;
          _delivered = false;
          _message = WhatsappFailureReasonAr.parse(row?.error).messageAr;
        });
      } else if (polls >= widget.maxPolls) {
        timer.cancel();
        setState(() {
          _busy = false;
          _delivered = null;
          _message =
              'لم يصلنا تأكيد الوصول بعد. تحقق من هاتفك، وأعد التجربة إن لم تصل.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _delivered == true
        ? Colors.green.shade700
        : _delivered == false
            ? cs.error
            : cs.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phone,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'رقمك على واتساب'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_send()),
          child: const Text('أرسل رسالة تجربة لرقمي'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            textAlign: TextAlign.start,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }
}
