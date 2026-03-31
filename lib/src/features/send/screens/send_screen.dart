import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../rust/api/sync.dart' as rust_sync;

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  bool _isSending = false;
  String? _error;
  String? _txid;
  String _addressType = '';

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _validateAddress() async {
    final addr = _addressController.text.trim();
    if (addr.isEmpty) {
      setState(() => _addressType = '');
      return;
    }
    try {
      final result = await rust_sync.validateAddress(address: addr);
      setState(() => _addressType = result.isValid ? result.addressType : 'invalid');
    } catch (_) {
      setState(() => _addressType = 'invalid');
    }
  }

  Future<void> _send() async {
    setState(() { _isSending = true; _error = null; _txid = null; });

    try {
      final address = _addressController.text.trim();
      final amountZec = double.tryParse(_amountController.text.trim()) ?? 0;
      final amountZatoshi = (amountZec * 100000000).round();

      if (amountZatoshi <= 0) {
        setState(() { _error = 'Invalid amount'; _isSending = false; });
        return;
      }

      log('Send: to=$address amount=$amountZatoshi zatoshi');

      // send_to_address needs seed bytes + Sapling proving parameters (~50MB)
      // Parameter download is not yet implemented
      setState(() {
        _error = 'Send functionality requires Sapling proving parameters.\n'
            'Parameter download not yet implemented.';
        _isSending = false;
      });
    } catch (e) {
      log('Send: ERROR: $e');
      setState(() { _error = e.toString(); _isSending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send ZEC')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Recipient Address',
                  suffixIcon: _addressType.isNotEmpty
                      ? Icon(
                          _addressType == 'invalid' ? Icons.error : Icons.check_circle,
                          color: _addressType == 'invalid' ? Colors.red : Colors.green,
                        )
                      : null,
                ),
                onChanged: (_) => _validateAddress(),
                maxLines: 2,
              ),
              if (_addressType.isNotEmpty && _addressType != 'invalid')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Address type: $_addressType',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Amount (ZEC)',
                  hintText: '0.00000000',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _memoController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Memo (optional)',
                  helperText: 'Only available for shielded addresses',
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  )),
                ),
              ],
              if (_txid != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Transaction sent!', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('TxID: $_txid', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSending || _addressType == 'invalid' || _addressType.isEmpty
                      ? null
                      : _send,
                  child: _isSending
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
