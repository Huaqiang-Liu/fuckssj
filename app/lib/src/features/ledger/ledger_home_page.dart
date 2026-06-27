import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_repository.dart';
import '../../importer/ledger_snapshot.dart';
import '../../importer/suishouji_importer.dart';

class LedgerHomePage extends StatefulWidget {
  const LedgerHomePage({super.key});

  @override
  State<LedgerHomePage> createState() => _LedgerHomePageState();
}

class _LedgerHomePageState extends State<LedgerHomePage> {
  final _ledgerRepository = LedgerRepository();
  final _importer = SuiShouJiImporter();

  LedgerStoreState _storeState = const LedgerStoreState(
    ledgers: [],
    lastLedgerId: null,
  );
  LedgerInfo? _activeLedger;
  LedgerSnapshot? _snapshot;
  String? _errorMessage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialLedger();
  }

  Future<void> _loadInitialLedger() async {
    await _loadWithStatus(() async {
      final storeState = await _ledgerRepository.loadStoreState();
      final ledger = await _ledgerRepository.loadLastLedger();
      if (ledger == null) {
        return _LoadedLedgerState(
          storeState: storeState,
          activeLedger: null,
          snapshot: null,
        );
      }

      return _LoadedLedgerState(
        storeState: storeState,
        activeLedger: ledger,
        snapshot: await _importer.load(ledger.path),
      );
    });
  }

  Future<void> _importSqliteLedger() async {
    final name = await _requestLedgerName();
    if (name == null) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'sqlite3', 'db', 'db3'],
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) {
      return;
    }

    await _loadWithStatus(() async {
      await _ledgerRepository.importSqliteFile(
        name: name,
        sourcePath: sourcePath,
      );
      return _loadLastLedgerState();
    });
  }

  Future<void> _importKbfLedger() async {
    final name = await _requestLedgerName();
    if (name == null) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kbf'],
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) {
      return;
    }

    await _loadWithStatus(() async {
      await _ledgerRepository.importKbfFile(name: name, sourcePath: sourcePath);
      return _loadLastLedgerState();
    });
  }

  Future<void> _createBlankLedger() async {
    final name = await _requestLedgerName();
    if (name == null) {
      return;
    }

    await _loadWithStatus(() async {
      await _ledgerRepository.createEmptyLedger(name: name);
      return _loadLastLedgerState();
    });
  }

  Future<void> _openLedger(LedgerInfo ledger) async {
    await _loadWithStatus(() async {
      await _ledgerRepository.setLastLedger(ledger.id);
      return _LoadedLedgerState(
        storeState: await _ledgerRepository.loadStoreState(),
        activeLedger: ledger,
        snapshot: await _importer.load(ledger.path),
      );
    });
  }

  Future<String?> _requestLedgerName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return LedgerNameDialog(existingLedgers: _storeState.ledgers);
      },
    );
    if (name != null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    return name;
  }

  Future<_LoadedLedgerState> _loadLastLedgerState() async {
    final storeState = await _ledgerRepository.loadStoreState();
    final ledger = await _ledgerRepository.loadLastLedger();
    return _LoadedLedgerState(
      storeState: storeState,
      activeLedger: ledger,
      snapshot: ledger == null ? null : await _importer.load(ledger.path),
    );
  }

  Future<void> _loadWithStatus(
    Future<_LoadedLedgerState> Function() action,
  ) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final loaded = await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _storeState = loaded.storeState;
        _activeLedger = loaded.activeLedger;
        _snapshot = loaded.snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final activeLedger = _activeLedger;

    return Scaffold(
      appBar: AppBar(
        title: Text(activeLedger?.name ?? '随手记迁移账本'),
        actions: [
          if (_storeState.ledgers.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: '切换账本',
              onSelected: (ledgerId) {
                final ledger = _storeState.ledgers.firstWhere(
                  (item) => item.id == ledgerId,
                );
                _openLedger(ledger);
              },
              itemBuilder: (context) {
                return [
                  for (final ledger in _storeState.ledgers)
                    PopupMenuItem(value: ledger.id, child: Text(ledger.name)),
                ];
              },
              icon: const Icon(Icons.folder_open),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LedgerActions(
                loading: _loading,
                onCreateBlank: _createBlankLedger,
                onImportSqlite: _importSqliteLedger,
                onImportKbf: _importKbfLedger,
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (snapshot == null)
                const Expanded(child: Center(child: Text('创建或导入一个账本开始使用。')))
              else
                Expanded(
                  child: _LedgerSummary(
                    ledger: activeLedger,
                    snapshot: snapshot,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LedgerNameDialog extends StatefulWidget {
  const LedgerNameDialog({super.key, required this.existingLedgers});

  final List<LedgerInfo> existingLedgers;

  @override
  State<LedgerNameDialog> createState() => _LedgerNameDialogState();
}

class _LedgerNameDialogState extends State<LedgerNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitName() {
    try {
      final name = _controller.text.trim();
      validateLedgerName(name);
      final normalized = normalizeLedgerName(name);
      final duplicate = widget.existingLedgers.any(
        (ledger) => normalizeLedgerName(ledger.name) == normalized,
      );
      if (duplicate) {
        throw ArgumentError('账本名称已存在');
      }
      Navigator.of(context).pop(name);
    } on ArgumentError catch (error) {
      setState(() {
        final message = error.message;
        _errorText = message is String ? message : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('命名账本'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: LedgerRepository.maxLedgerNameLength,
        decoration: InputDecoration(labelText: '账本名称', errorText: _errorText),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submitName(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submitName, child: const Text('继续')),
      ],
    );
  }
}

class _LoadedLedgerState {
  const _LoadedLedgerState({
    required this.storeState,
    required this.activeLedger,
    required this.snapshot,
  });

  final LedgerStoreState storeState;
  final LedgerInfo? activeLedger;
  final LedgerSnapshot? snapshot;
}

class _LedgerActions extends StatelessWidget {
  const _LedgerActions({
    required this.loading,
    required this.onCreateBlank,
    required this.onImportSqlite,
    required this.onImportKbf,
  });

  final bool loading;
  final VoidCallback onCreateBlank;
  final VoidCallback onImportSqlite;
  final VoidCallback onImportKbf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: loading ? null : onCreateBlank,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('创建空白账本'),
        ),
        OutlinedButton.icon(
          onPressed: loading ? null : onImportSqlite,
          icon: const Icon(Icons.storage),
          label: const Text('从 SQLite 创建'),
        ),
        OutlinedButton.icon(
          onPressed: loading ? null : onImportKbf,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('从 KBF 创建'),
        ),
      ],
    );
  }
}

class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({required this.ledger, required this.snapshot});

  final LedgerInfo? ledger;
  final LedgerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final transactions = snapshot.transactions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          snapshot.hasSuiShouJiTables
              ? '已读取 ${transactions.length} 条最近流水'
              : '空白账本已创建',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        if (ledger != null)
          Text(
            '${ledger!.sourceKind.label} · ${ledger!.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const Divider(height: 24),
        if (transactions.isEmpty)
          const Expanded(child: Center(child: Text('暂无流水')))
        else
          Expanded(
            child: ListView.separated(
              itemCount: transactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return _TransactionTile(record: transactions[index]);
              },
            ),
          ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  _TransactionTile({required this.record});

  final TransactionRecord record;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final isIncome = record.kind == TransactionKind.income;
    final amountColor = isIncome
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(record.categoryPath),
      subtitle: Text(_dateFormat.format(record.tradeTime)),
      trailing: Text(
        '${isIncome ? '+' : '-'}${record.amount}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
