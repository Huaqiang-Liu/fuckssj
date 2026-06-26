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

  LedgerSnapshot? _snapshot;
  String? _errorMessage;
  bool _loading = false;

  Future<void> _importLedger() async {
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
      final ledgerFile = await _ledgerRepository.importSqliteFile(sourcePath);
      return _importer.load(ledgerFile.path);
    });
  }

  Future<void> _createBlankLedger() async {
    await _loadWithStatus(() async {
      final ledgerFile = await _ledgerRepository.createEmptyLedger();
      return _importer.load(ledgerFile.path);
    });
  }

  Future<void> _loadWithStatus(Future<LedgerSnapshot> Function() action) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final snapshot = await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('随手记迁移账本')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : _importLedger,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('导入 SQLite'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _createBlankLedger,
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('新建空白账本'),
                  ),
                ],
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
                const Expanded(
                  child: Center(child: Text('请选择恢复后的 mymoney.sqlite，或新建空白账本。')),
                )
              else
                Expanded(child: _LedgerSummary(snapshot: snapshot)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({required this.snapshot});

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
        Text(
          snapshot.databasePath,
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
