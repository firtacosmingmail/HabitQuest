import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import '../dates.dart';

/// Create (no [quote]) or edit a quote, including its day. Saves through
/// `POST /quotes` / `PUT /quotes?id=` and returns the saved quote, or null
/// when cancelled. A `day_taken` conflict is shown inline.
Future<AdminQuote?> showQuoteEditor(
  BuildContext context, {
  required AdminApi api,
  AdminQuote? quote,
  String? initialDay,
}) => showDialog<AdminQuote>(
  context: context,
  builder: (_) => QuoteEditor(api: api, quote: quote, initialDay: initialDay),
);

class QuoteEditor extends StatefulWidget {
  final AdminApi api;
  final AdminQuote? quote;
  final String? initialDay;

  const QuoteEditor({
    super.key,
    required this.api,
    this.quote,
    this.initialDay,
  });

  @override
  State<QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<QuoteEditor> {
  late final TextEditingController _text;
  late final TextEditingController _author;
  String? _day;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.quote?.text ?? '');
    _author = TextEditingController(text: widget.quote?.author ?? '');
    _day = widget.quote?.day ?? widget.initialDay;
  }

  @override
  void dispose() {
    _text.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final initial = _day != null ? parseDateKey(_day!) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Schedule for',
    );
    if (picked != null) setState(() => _day = dateKey(picked));
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'The quote text is required.');
      return;
    }
    if (text.runes.length > 500) {
      setState(() => _error = 'At most 500 characters.');
      return;
    }
    if (_author.text.trim().runes.length > 200) {
      setState(() => _error = 'The author is at most 200 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = QuoteDraft(text: text, author: _author.text, day: _day);
    try {
      final saved = widget.quote == null
          ? await widget.api.createQuote(draft)
          : await widget.api.updateQuote(widget.quote!.id, draft);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.code == ApiException.dayTaken
            ? 'Another quote is already scheduled on $_day.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.quote != null;
    return AlertDialog(
      title: Text(editing ? 'Edit quote' : 'New quote'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('quote-text'),
              controller: _text,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Quote'),
            ),
            TextField(
              key: const ValueKey('quote-author'),
              controller: _author,
              decoration: const InputDecoration(
                labelText: 'Author',
                helperText: 'Leave empty for anonymous quotes and proverbs',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.event, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _day == null
                        ? 'Not scheduled'
                        : 'Scheduled for ${longDate(parseDateKey(_day!))}',
                    key: const ValueKey('quote-day'),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _pickDay,
                  child: Text(_day == null ? 'Schedule' : 'Reschedule'),
                ),
                if (_day != null)
                  TextButton(
                    key: const ValueKey('quote-clear-day'),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _day = null),
                    child: const Text('Unschedule'),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('quote-save'),
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

/// Asks before deleting; returns true when confirmed.
Future<bool> confirmDelete(BuildContext context, AdminQuote q) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this quote?'),
      content: Text(
        '“${q.text}”\n\nIt is removed for everyone, together with its '
        '${q.loves} love${q.loves == 1 ? '' : 's'}. To keep it but free its '
        'day, unschedule it instead.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
