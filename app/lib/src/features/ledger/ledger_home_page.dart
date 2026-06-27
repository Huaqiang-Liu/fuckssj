import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

import '../../app/app_snack_bar.dart';
import '../../data/app_settings_store.dart';
import '../../data/exchange_rate_store.dart';
import '../../data/ledger_configuration_store.dart';
import '../../data/ledger_repository.dart';
import '../../data/ledger_transaction_repository.dart';
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

  Future<void> _openLedger(LedgerInfo ledger) async {
    await _loadWithStatus(() async {
      await _ledgerRepository.setLastLedger(ledger.id);
      final configFile = await _ledgerRepository.ensureLedgerConfiguration(
        ledger,
      );
      final ledgerWithConfig = ledger.copyWith(
        configurationPath: configFile.path,
      );
      return _LoadedLedgerState(
        storeState: await _ledgerRepository.loadStoreState(),
        activeLedger: ledgerWithConfig,
        snapshot: await _importer.load(ledgerWithConfig.path),
      );
    });
  }

  Future<void> _returnToHome() async {
    final storeState = await _ledgerRepository.loadStoreState();
    if (!mounted) {
      return;
    }
    setState(() {
      _storeState = storeState;
      _activeLedger = null;
      _snapshot = null;
      _errorMessage = null;
      _loading = false;
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

  void _showPendingFeature(String featureName) {
    showAppSnackBar(context, '$featureName 将在后续迭代实现');
  }

  @override
  Widget build(BuildContext context) {
    final activeLedger = _activeLedger;
    final snapshot = _snapshot;

    if (_loading && activeLedger == null && snapshot == null) {
      return const _StartupLoadingPage();
    }

    if (activeLedger != null && snapshot != null) {
      return LedgerPage(
        ledger: activeLedger,
        snapshot: snapshot,
        loading: _loading,
        errorMessage: _errorMessage,
        onBackToHome: _returnToHome,
      );
    }

    return HomePage(
      storeState: _storeState,
      loading: _loading,
      errorMessage: _errorMessage,
      onCreateBlank: _createBlankLedger,
      onImportSqlite: _importSqliteLedger,
      onImportKbf: _importKbfLedger,
      onOpenLedger: _openLedger,
      onRenameLedger: _renameLedger,
      onEditLedgerNote: _editLedgerNote,
      onExportLedger: _exportLedger,
      onDeleteLedger: _deleteLedger,
      onPendingFeature: _showPendingFeature,
    );
  }

  Future<void> _refreshStoreState() async {
    final storeState = await _ledgerRepository.loadStoreState();
    if (!mounted) {
      return;
    }
    setState(() {
      _storeState = storeState;
    });
  }

  Future<void> _renameLedger(LedgerInfo ledger) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => LedgerNameDialog(
        existingLedgers: _storeState.ledgers,
        initialName: ledger.name,
        excludedLedgerId: ledger.id,
        title: '重命名账本',
        actionLabel: '保存',
      ),
    );
    if (name == null) {
      return;
    }
    try {
      await _ledgerRepository.renameLedger(ledgerId: ledger.id, name: name);
      await _refreshStoreState();
      if (mounted) {
        showAppSnackBar(context, '账本已重命名');
      }
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '重命名失败：$error');
      }
    }
  }

  Future<void> _editLedgerNote(LedgerInfo ledger) async {
    final note = await _showLedgerNoteDialog(context, ledger: ledger);
    if (note == null) {
      return;
    }
    try {
      await _ledgerRepository.updateLedgerNote(
        ledgerId: ledger.id,
        note: note,
      );
      await _refreshStoreState();
      if (mounted) {
        showAppSnackBar(context, '备注已保存');
      }
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '保存备注失败：$error');
      }
    }
  }

  Future<void> _exportLedger(LedgerInfo ledger) async {
    try {
      final source = File(ledger.path);
      if (!source.existsSync()) {
        throw StateError('账本文件不存在：${ledger.path}');
      }
      final destinationPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出账本',
        fileName: _exportLedgerFileName(ledger),
        type: FileType.custom,
        allowedExtensions: const ['sqlite'],
        bytes: await source.readAsBytes(),
      );
      if (destinationPath == null) {
        return;
      }
      if (mounted) {
        showAppSnackBar(context, '账本已导出');
      }
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '导出失败：$error');
      }
    }
  }

  Future<void> _deleteLedger(LedgerInfo ledger) async {
    final confirmed = await _showDeleteLedgerDialog(context, ledger: ledger);
    if (confirmed != true) {
      return;
    }
    try {
      await _ledgerRepository.deleteLedger(ledger.id);
      await _refreshStoreState();
      if (mounted) {
        showAppSnackBar(context, '账本已删除');
      }
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '删除账本失败：$error');
      }
    }
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.storeState,
    required this.loading,
    required this.errorMessage,
    required this.onCreateBlank,
    required this.onImportSqlite,
    required this.onImportKbf,
    required this.onOpenLedger,
    required this.onRenameLedger,
    required this.onEditLedgerNote,
    required this.onExportLedger,
    required this.onDeleteLedger,
    required this.onPendingFeature,
  });

  final LedgerStoreState storeState;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onCreateBlank;
  final VoidCallback onImportSqlite;
  final VoidCallback onImportKbf;
  final ValueChanged<LedgerInfo> onOpenLedger;
  final ValueChanged<LedgerInfo> onRenameLedger;
  final ValueChanged<LedgerInfo> onEditLedgerNote;
  final ValueChanged<LedgerInfo> onExportLedger;
  final ValueChanged<LedgerInfo> onDeleteLedger;
  final ValueChanged<String> onPendingFeature;

  @override
  Widget build(BuildContext context) {
    final ledgers = storeState.ledgers;

    return Scaffold(
      appBar: AppBar(title: const Text('账本')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            if (errorMessage != null) ...[
              _ErrorText(message: errorMessage!),
              const SizedBox(height: 16),
            ],
            if (ledgers.isEmpty)
              const _EmptyLedgerState()
            else ...[
              Text('已有账本', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final ledger in ledgers)
                _LedgerListTile(
                  ledger: ledger,
                  isLastOpened: ledger.id == storeState.lastLedgerId,
                  enabled: !loading,
                  onOpen: () => onOpenLedger(ledger),
                  onRename: () => onRenameLedger(ledger),
                  onEditNote: () => onEditLedgerNote(ledger),
                  onExport: () => onExportLedger(ledger),
                  onDelete: () => onDeleteLedger(ledger),
                  onPendingFeature: onPendingFeature,
                ),
              const SizedBox(height: 24),
            ],
            Text('创建账本', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _LedgerActions(
              loading: loading,
              onCreateBlank: onCreateBlank,
              onImportSqlite: onImportSqlite,
              onImportKbf: onImportKbf,
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _HomeFooter(),
    );
  }
}

class _HomeFooter extends StatelessWidget {
  const _HomeFooter();

  static const _version = '1.0.0+1';
  static const _license = 'MIT';

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          '版本 $_version · 开源协议：$_license',
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}

class LedgerPage extends StatefulWidget {
  const LedgerPage({
    super.key,
    required this.ledger,
    required this.snapshot,
    required this.loading,
    required this.errorMessage,
    required this.onBackToHome,
  });

  final LedgerInfo ledger;
  final LedgerSnapshot snapshot;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onBackToHome;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  final _importer = SuiShouJiImporter();
  final _minAmountController = TextEditingController();
  final _maxAmountController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  Map<String, Object?>? _ledgerConfig;
  Set<String>? _selectedAccounts;
  Set<String>? _selectedCategories;
  Set<String>? _selectedCurrencies;
  bool _includeIncome = true;
  bool _includeExpense = true;
  bool _querying = false;
  late LedgerSnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.snapshot;
    _loadQueryConfig();
  }

  @override
  void didUpdateWidget(covariant LedgerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ledger.id != widget.ledger.id) {
      _snapshot = widget.snapshot;
      _selectedAccounts = null;
      _selectedCategories = null;
      _selectedCurrencies = null;
      _loadQueryConfig();
    } else if (oldWidget.snapshot != widget.snapshot) {
      _snapshot = widget.snapshot;
    }
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadQueryConfig() async {
    try {
      final config = await _loadLedgerConfig(widget.ledger);
      if (!mounted) {
        return;
      }
      setState(() {
        _ledgerConfig = config;
        _selectedAccounts = _intersectSelection(
          _selectedAccounts,
          _accountFilterOptions(config),
        );
        _selectedCategories = _intersectSelection(
          _selectedCategories,
          _categoryFilterOptions(config),
        );
        _selectedCurrencies = _intersectSelection(
          _selectedCurrencies,
          _currencyFilterOptions(config),
        );
      });
    } catch (error) {
      if (mounted) {
        showAppSnackBar(context, '读取筛选配置失败：$error');
      }
    }
  }

  Future<void> _submitQuery() async {
    final query = _buildQuery();
    if (query == null) {
      return;
    }

    setState(() {
      _querying = true;
    });
    try {
      final result = await _importer.query(widget.ledger.path, query);
      if (!mounted) {
        return;
      }
      setState(() {
        _querying = false;
      });
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => TransactionListPage(
              ledger: widget.ledger,
              snapshot: result,
              query: query,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, '查询失败：$error');
    } finally {
      if (mounted && _querying) {
        setState(() {
          _querying = false;
        });
      }
    }
  }

  Future<void> _openTransactionEditor({TransactionRecord? record}) async {
    final config = _ledgerConfig ?? await _loadLedgerConfig(widget.ledger);
    _ledgerConfig = config;
    if (!mounted) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TransactionEditPage(
          ledger: widget.ledger,
          config: config,
          record: record,
        ),
      ),
    );
    if (changed == true) {
      final snapshot = await _importer.load(widget.ledger.path);
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
      });
    }
  }

  TransactionQuery? _buildQuery() {
    if (!_includeIncome && !_includeExpense) {
      _showQueryError('收入和支出不能同时取消');
      return null;
    }
    if (_selectedAccounts?.isEmpty == true) {
      _showQueryError('账户不能全都取消');
      return null;
    }
    if (_selectedCategories?.isEmpty == true) {
      _showQueryError('分类不能全都取消');
      return null;
    }
    if (_selectedCurrencies?.isEmpty == true) {
      _showQueryError('币种不能全都取消');
      return null;
    }

    final minAmount = _parseAmount(_minAmountController.text, '最低金额');
    if (minAmount == null && _minAmountController.text.trim().isNotEmpty) {
      return null;
    }
    final maxAmount = _parseAmount(_maxAmountController.text, '最高金额');
    if (maxAmount == null && _maxAmountController.text.trim().isNotEmpty) {
      return null;
    }
    if (minAmount != null && maxAmount != null && minAmount > maxAmount) {
      _showQueryError('最低金额不能大于最高金额');
      return null;
    }

    final startDate = _startDate;
    final endDate = _endDate;
    if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
      _showQueryError('开始时间不能晚于结束时间');
      return null;
    }

    return TransactionQuery(
      startDate: startDate,
      endDate: endDate?.add(const Duration(days: 1)),
      includeIncome: _includeIncome,
      includeExpense: _includeExpense,
      minAmount: minAmount,
      maxAmount: maxAmount,
      noteKeyword: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      accountNames: _selectedAccounts?.toList(),
      categoryPaths: _selectedCategories?.toList(),
      currencyCodes: _selectedCurrencies?.toList(),
    );
  }

  double? _parseAmount(String text, String label) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final amount = double.tryParse(trimmed);
    if (amount == null || amount < 0) {
      _showQueryError('$label 必须是非负数字');
      return null;
    }
    return amount;
  }

  void _showQueryError(String message) {
    showAppSnackBar(context, message);
  }

  void _resetQuery() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _includeIncome = true;
      _includeExpense = true;
      _selectedAccounts = null;
      _selectedCategories = null;
      _selectedCurrencies = null;
      _minAmountController.clear();
      _maxAmountController.clear();
      _noteController.clear();
    });
  }

  Future<void> _pickAccounts() async {
    final options = _accountFilterOptions(_ledgerConfig);
    final selected = await _showTreeMultiSelectFilter(
      context,
      title: '选择账户',
      nodes: _accountFilterTree(_ledgerConfig),
      options: options,
      selectedValues: _selectedAccounts,
    );
    if (selected != null) {
      setState(() {
        _selectedAccounts = _normalizedFilterSelection(selected, options);
      });
    }
  }

  Future<void> _pickCategories() async {
    final options = _categoryFilterOptions(_ledgerConfig);
    final selected = await _showTreeMultiSelectFilter(
      context,
      title: '选择分类',
      nodes: _categoryFilterTree(_ledgerConfig),
      options: options,
      selectedValues: _selectedCategories,
    );
    if (selected != null) {
      setState(() {
        _selectedCategories = _normalizedFilterSelection(selected, options);
      });
    }
  }

  Future<void> _pickCurrencies() async {
    final options = _currencyFilterOptions(_ledgerConfig);
    final selected = await _showMultiSelectFilter(
      context,
      title: '选择币种',
      options: options,
      selectedValues: _selectedCurrencies,
    );
    if (selected != null) {
      setState(() {
        _selectedCurrencies = _normalizedFilterSelection(selected, options);
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(initialDate: _startDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(initialDate: _endDate ?? DateTime.now());
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<DateTime?> _pickDate({required DateTime initialDate}) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回首页',
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackToHome,
        ),
        title: Text(widget.ledger.name),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.loading || _querying) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            if (widget.errorMessage != null) ...[
              _ErrorText(message: widget.errorMessage!),
              const SizedBox(height: 16),
            ],
            _DashboardCards(snapshot: _snapshot),
            const SizedBox(height: 16),
            _QueryPanel(
              startDate: _startDate,
              endDate: _endDate,
              includeIncome: _includeIncome,
              includeExpense: _includeExpense,
              minAmountController: _minAmountController,
              maxAmountController: _maxAmountController,
              noteController: _noteController,
              accountLabel: _filterLabel(_selectedAccounts),
              categoryLabel: _filterLabel(_selectedCategories),
              currencyLabel: _filterLabel(_selectedCurrencies),
              onPickAccounts: _pickAccounts,
              onPickStartDate: _pickStartDate,
              onPickEndDate: _pickEndDate,
              onPickCurrencies: _pickCurrencies,
              onPickCategories: _pickCategories,
              onClearStartDate: () => setState(() => _startDate = null),
              onClearEndDate: () => setState(() => _endDate = null),
              onIncludeIncomeChanged: (value) {
                setState(() {
                  _includeIncome = value;
                });
              },
              onIncludeExpenseChanged: (value) {
                setState(() {
                  _includeExpense = value;
                });
              },
              onReset: _resetQuery,
              onQuery: _querying ? null : _submitQuery,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openTransactionEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('新建'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                tooltip: '账本设置',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          LedgerSettingsPage(ledger: widget.ledger),
                    ),
                  );
                  if (mounted) {
                    await _loadQueryConfig();
                  }
                },
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransactionListPage extends StatefulWidget {
  const TransactionListPage({
    super.key,
    required this.ledger,
    required this.snapshot,
    required this.query,
  });

  final LedgerInfo ledger;
  final LedgerSnapshot snapshot;
  final TransactionQuery query;

  @override
  State<TransactionListPage> createState() => _TransactionListPageState();
}

class _TransactionListPageState extends State<TransactionListPage> {
  final _importer = SuiShouJiImporter();
  final _scrollController = ScrollController();
  late final List<TransactionRecord> _transactions;
  late bool _hasMore;
  bool _loadingMore = false;
  Map<String, Object?>? _ledgerConfig;

  @override
  void initState() {
    super.initState();
    _transactions = [...widget.snapshot.transactions];
    _hasMore = widget.snapshot.transactions.length >= widget.query.limit;
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _maybeLoadMore() async {
    if (!_hasMore || _loadingMore || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 240) {
      return;
    }

    setState(() {
      _loadingMore = true;
    });
    try {
      final next = await _importer.query(
        widget.ledger.path,
        widget.query.copyWith(offset: _transactions.length),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _transactions.addAll(next.transactions);
        _hasMore = next.transactions.length >= widget.query.limit;
        _loadingMore = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
        showAppSnackBar(context, '继续加载失败：$error');
      }
    }
  }

  Future<void> _openTransactionEditor(TransactionRecord record) async {
    final config = _ledgerConfig ?? await _loadLedgerConfig(widget.ledger);
    _ledgerConfig = config;
    if (!mounted) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => TransactionEditPage(
          ledger: widget.ledger,
          config: config,
          record: record,
        ),
      ),
    );
    if (changed == true) {
      final refreshed = await _importer.query(widget.ledger.path, widget.query);
      if (!mounted) {
        return;
      }
      setState(() {
        _transactions
          ..clear()
          ..addAll(refreshed.transactions);
        _hasMore = refreshed.transactions.length >= widget.query.limit;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('查询结果')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _LedgerSummary(
            ledger: widget.ledger,
            snapshot: LedgerSnapshot(
              databasePath: widget.snapshot.databasePath,
              transactions: _transactions,
              hasSuiShouJiTables: widget.snapshot.hasSuiShouJiTables,
            ),
            title: '查询到 ${_transactions.length} 条流水',
            subtitle: _querySummary(widget.query),
            scrollController: _scrollController,
            loadingMore: _loadingMore,
            onRecordTap: _openTransactionEditor,
          ),
        ),
      ),
    );
  }
}

class LedgerSettingsPage extends StatelessWidget {
  const LedgerSettingsPage({super.key, required this.ledger});

  final LedgerInfo ledger;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账本设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(ledger.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${ledger.sourceKind.label} · 创建于 ${_formatDateTime(ledger.createdAt.toLocal())}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              ledger.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (ledger.configurationPath != null) ...[
              const SizedBox(height: 8),
              Text(
                '配置：${ledger.configurationPath}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Divider(height: 32),
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: '主题设置',
              subtitle: '浅色、深色、跟随系统；保存为全局唯一设置',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const ThemeSettingsPage(),
                ),
              ),
            ),
            _SettingsTile(
              icon: Icons.category_outlined,
              title: '分类管理',
              subtitle: '当前账本独立维护',
              onTap: () => _openConfigPage(
                context,
                ledger: ledger,
                title: '分类管理',
                section: 'categories',
              ),
            ),
            _SettingsTile(
              icon: Icons.account_balance_wallet_outlined,
              title: '账户管理',
              subtitle: '当前账本独立维护',
              onTap: () => _openConfigPage(
                context,
                ledger: ledger,
                title: '账户管理',
                section: 'accounts',
              ),
            ),
            _SettingsTile(
              icon: Icons.currency_exchange,
              title: '外币管理',
              subtitle: '当前账本常用币种列表',
              onTap: () => _openConfigPage(
                context,
                ledger: ledger,
                title: '外币管理',
                section: 'currencies',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = appSettingsController.settings;
  }

  Future<void> _update(AppSettings settings) async {
    setState(() {
      _settings = settings;
    });
    await appSettingsController.update(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('显示模式', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('白天'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('黑夜'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('跟随系统'),
                ),
              ],
              selected: {_settings.themeMode},
              onSelectionChanged: (value) {
                _update(_settings.copyWith(themeMode: value.single));
              },
            ),
            const SizedBox(height: 24),
            Text('字号加大', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const [
                  (value: 0, label: '默认'),
                  (value: 1, label: '+1'),
                  (value: 2, label: '+2'),
                  (value: 3, label: '+3'),
                ])
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _settings.fontSizeBias == option.value,
                    onSelected: (_) {
                      _update(
                        _settings.copyWith(fontSizeBias: option.value),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '只提供比默认字号更大的选项，不提供更小字号。字号会立即应用到整个 App。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionEditPage extends StatefulWidget {
  const TransactionEditPage({
    super.key,
    required this.ledger,
    required this.config,
    this.record,
  });

  final LedgerInfo ledger;
  final Map<String, Object?> config;
  final TransactionRecord? record;

  @override
  State<TransactionEditPage> createState() => _TransactionEditPageState();
}

class _TransactionEditPageState extends State<TransactionEditPage> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late TransactionKind _kind;
  late DateTime _tradeTime;
  _TransactionChoice? _category;
  _TransactionChoice? _account;
  String _currencyCode = 'CNY';
  bool _saving = false;

  bool get _isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _kind = record?.kind ?? TransactionKind.expense;
    _tradeTime = record?.tradeTime ?? DateTime.now();
    _amountController.text = record?.amount ?? '';
    _noteController.text = record?.note ?? '';
    _currencyCode = record?.currencyCode ?? 'CNY';
    _category = _initialCategoryChoice(record);
    _account = _initialAccountChoice(record);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑流水' : '记一笔'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: '删除',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_saving) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            SegmentedButton<TransactionKind>(
              segments: const [
                ButtonSegment(value: TransactionKind.expense, label: Text('支出')),
                ButtonSegment(value: TransactionKind.income, label: Text('收入')),
              ],
              selected: {_kind},
              onSelectionChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _kind = value.single;
                        _category = _initialCategoryChoice(null);
                      });
                    },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '金额',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _pickCurrency,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currencyFlag(_currencyCode),
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 6),
                        Text(_currencyCode),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _EditPickerTile(
              label: '分类',
              value: _category?.value ?? '请选择',
              onTap: _saving ? null : _pickCategory,
            ),
            _EditPickerTile(
              label: '账户',
              value: _account?.label ?? '请选择',
              onTap: _saving ? null : _pickAccount,
            ),
            _EditPickerTile(
              label: '时间',
              value: _formatDateTime(_tradeTime),
              onTap: _saving ? null : _pickTradeTime,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              enabled: !_saving,
              minLines: 3,
              maxLines: 5,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '备注',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ),
      ),
    );
  }

  _TransactionChoice? _initialCategoryChoice(TransactionRecord? record) {
    final choices = _categoryEditChoices(widget.config, _kind);
    if (record != null) {
      final categoryId = record.categoryId;
      if (categoryId != null) {
        for (final choice in choices) {
          if (choice.sqliteId == categoryId) {
            return choice;
          }
        }
      }
      for (final choice in choices) {
        if (choice.value == record.categoryPath) {
          return choice;
        }
      }
      final secondCategory = record.secondCategory;
      if (secondCategory != null && secondCategory.isNotEmpty) {
        final parent = _TransactionChoice(
          id: record.parentCategoryId == null
              ? 'record_category_parent'
              : 'ssj_${record.parentCategoryId}',
          label: record.firstCategory,
          value: record.firstCategory,
          sqliteId: record.parentCategoryId,
        );
        return _TransactionChoice(
          id: categoryId == null ? 'record_category' : 'ssj_$categoryId',
          label: record.categoryPath,
          value: record.categoryPath,
          sqliteId: categoryId,
          parent: parent,
        );
      }
      return _TransactionChoice(
        id: categoryId == null ? 'record_category' : 'ssj_$categoryId',
        label: record.categoryPath,
        value: record.categoryPath,
        sqliteId: categoryId,
      );
    }
    return choices.isEmpty ? null : choices.first;
  }

  _TransactionChoice? _initialAccountChoice(TransactionRecord? record) {
    final choices = _accountEditChoices(widget.config);
    if (record != null) {
      final accountId = record.accountId;
      if (accountId != null) {
        for (final choice in choices) {
          if (choice.sqliteId == accountId) {
            return choice;
          }
        }
      }
      final accountName = record.accountName;
      if (accountName != null && accountName.isNotEmpty) {
        for (final choice in choices) {
          if (choice.value == accountName) {
            return choice;
          }
        }
        return _TransactionChoice(
          id: accountId == null ? 'record_account' : 'ssj_account_$accountId',
          label: accountName,
          value: accountName,
          sqliteId: accountId,
        );
      }
    }
    return choices.isEmpty ? null : choices.first;
  }

  Future<void> _pickCategory() async {
    final picked = await _showCategoryChoicePicker(
      context,
      config: widget.config,
      kind: _kind,
    );
    if (picked != null) {
      setState(() {
        _category = picked;
      });
    }
  }

  Future<void> _pickAccount() async {
    final picked = await _showTransactionChoicePicker(
      context,
      title: '选择账户',
      choices: _accountEditChoices(widget.config),
    );
    if (picked != null) {
      setState(() {
        _account = picked;
      });
    }
  }

  Future<void> _pickCurrency() async {
    final picked = await _showTransactionChoicePicker(
      context,
      title: '选择币种',
      choices: _currencyEditChoices(widget.config),
    );
    if (picked != null) {
      setState(() {
        _currencyCode = picked.value;
      });
    }
  }

  Future<void> _pickTradeTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _tradeTime,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_tradeTime),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _tradeTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      showAppSnackBar(context, '金额必须是大于 0 的数字');
      return;
    }
    final category = _category;
    if (category == null) {
      showAppSnackBar(context, '请选择分类');
      return;
    }
    final account = _account;
    if (account == null) {
      showAppSnackBar(context, '请选择账户');
      return;
    }

    setState(() {
      _saving = true;
    });
    try {
      await LedgerTransactionRepository().save(
        databasePath: widget.ledger.path,
        record: widget.record,
        draft: LedgerTransactionDraft(
          kind: _kind,
          amountText: amountText,
          tradeTime: _tradeTime,
          category: _toLedgerTransactionChoice(category),
          account: _toLedgerTransactionChoice(account),
          currencyCode: _currencyCode,
          note: _noteController.text.trim(),
        ),
      );
      try {
        await _recordRecentCategoryUsage(
          widget.ledger,
          widget.config,
          _kind,
          category,
        );
      } catch (_) {
        // 最近使用只是输入辅助，不能影响流水保存结果。
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
        });
        showAppSnackBar(context, '保存流水失败：$error');
      }
    }
  }

  Future<void> _delete() async {
    final record = widget.record;
    if (record == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除这条流水？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await LedgerTransactionRepository().delete(widget.ledger.path, record.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
        });
        showAppSnackBar(context, '删除流水失败：$error');
      }
    }
  }
}

LedgerTransactionChoice _toLedgerTransactionChoice(_TransactionChoice choice) {
  final parent = choice.parent;
  return LedgerTransactionChoice(
    id: choice.id,
    label: choice.label,
    value: choice.value,
    sqliteId: choice.sqliteId,
    parent: parent == null ? null : _toLedgerTransactionChoice(parent),
  );
}

class _EditPickerTile extends StatelessWidget {
  const _EditPickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

void _openConfigPage(
  BuildContext context, {
  required LedgerInfo ledger,
  required String title,
  required String section,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          LedgerConfigPage(ledger: ledger, title: title, section: section),
    ),
  );
}

class LedgerConfigPage extends StatefulWidget {
  const LedgerConfigPage({
    super.key,
    required this.ledger,
    required this.title,
    required this.section,
  });

  final LedgerInfo ledger;
  final String title;
  final String section;

  @override
  State<LedgerConfigPage> createState() => _LedgerConfigPageState();
}

class _LedgerConfigPageState extends State<LedgerConfigPage> {
  Map<String, Object?>? _config;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await _loadLedgerConfig(widget.ledger);
      final normalizedConfig = _normalizeLedgerConfig(config);
      if (jsonEncode(normalizedConfig) != jsonEncode(config)) {
        await _saveLedgerConfig(widget.ledger, normalizedConfig);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _config = normalizedConfig;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _save(Map<String, Object?> config) async {
    final normalizedConfig = _normalizeLedgerConfig(config);
    await _saveLedgerConfig(widget.ledger, normalizedConfig);
    if (!mounted) {
      return;
    }
    setState(() {
      _config = normalizedConfig;
    });
  }

  Future<void> _addRoot({String? direction}) async {
    final name = await _requestConfigName(context, title: '新增一级条目');
    if (name == null) {
      return;
    }
    final config = _copyConfig();
    if (widget.section == 'categories') {
      final group = _categoryGroup(config, direction ?? 'expense');
      final items = _mutableList(group['items']);
      if (_containsName(items, name)) {
        showAppSnackBar(context, '同级名称已存在');
        return;
      }
      items.add(_newConfigNode(name));
      group['items'] = items;
    } else if (widget.section == 'accounts') {
      final items = _mutableList(config['accounts']);
      if (_containsName(items, name)) {
        showAppSnackBar(context, '账户名称已存在');
        return;
      }
      items.add(_newConfigNode(name));
      config['accounts'] = items;
    }
    await _save(config);
  }

  Future<void> _addChild(String parentId) async {
    final name = await _requestConfigName(context, title: '新增二级条目');
    if (name == null) {
      return;
    }
    final config = _copyConfig();
    final parent = _findNode(config[widget.section], parentId);
    if (parent == null) {
      return;
    }
    final children = _mutableList(parent['children']);
    if (_containsName(children, name)) {
      showAppSnackBar(context, '同级名称已存在');
      return;
    }
    children.add(_newConfigNode(name));
    parent['children'] = children;
    await _save(config);
  }

  Future<void> _editNode(String nodeId, String title) async {
    final result = await _showConfigActionDialog(context, title: title);
    if (result == null) {
      return;
    }
    final config = _copyConfig();
    if (result.delete) {
      await _deleteLedgerRowsForConfigNode(
        config: config,
        databasePath: widget.ledger.path,
        section: widget.section,
        nodeId: nodeId,
      );
      if (!_removeNode(config[widget.section], nodeId)) {
        return;
      }
      await _save(config);
      return;
    }

    final name = result.name.trim();
    if (name.isEmpty || name == title) {
      return;
    }
    final node = _findNode(config[widget.section], nodeId);
    if (node == null) {
      return;
    }
    await _renameLedgerConfigNode(
      databasePath: widget.ledger.path,
      section: widget.section,
      nodeId: nodeId,
      name: name,
    );
    node['name'] = name;
    await _save(config);
  }

  Future<void> _disableCurrency(String code) async {
    if (code == 'CNY') {
      showAppSnackBar(context, '人民币不能删除');
      return;
    }
    final config = _copyConfig();
    final currencies = _mutableList(config['currencies']);
    for (final item in currencies) {
      if (item is Map<String, Object?> && item['code'] == code) {
        item['enabled'] = false;
      }
    }
    config['currencies'] = currencies;
    await _save(config);
  }

  Future<void> _openAddCurrencyPage() async {
    final config = _copyConfig();
    final updated = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(builder: (context) => AddCurrencyPage(config: config)),
    );
    if (updated != null) {
      await _save(updated);
    }
  }

  Map<String, Object?> _copyConfig() {
    return _jsonMapCopy(_config ?? const {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.section == 'currencies')
            IconButton(
              tooltip: '添加常用外币',
              onPressed: _openAddCurrencyPage,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _ErrorText(message: error.toString()),
      );
    }
    final config = _config;
    if (config == null) {
      return const Center(child: Text('配置文件为空'));
    }

    final value = config[widget.section];
    if (value is! List) {
      return const Center(child: Text('暂无配置'));
    }

    if (widget.section == 'categories') {
      final expenseItems = _categoryItems(value, 'expense');
      final incomeItems = _categoryItems(value, 'income');
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '支出分类'),
                Tab(text: '收入分类'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CategoryTabView(
                    items: expenseItems,
                    emptyText: '暂无支出分类',
                    onAddRoot: () => _addRoot(direction: 'expense'),
                    onAddChild: _addChild,
                    onEditNode: _editNode,
                  ),
                  _CategoryTabView(
                    items: incomeItems,
                    emptyText: '暂无收入分类',
                    onAddRoot: () => _addRoot(direction: 'income'),
                    onAddChild: _addChild,
                    onEditNode: _editNode,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (widget.section == 'currencies') {
      return _CurrencyConfigList(config: config, onDelete: _disableCurrency);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addRoot(),
              icon: const Icon(Icons.add),
              label: const Text('新增一级账户'),
            ),
          ),
        ),
        Expanded(
          child: _ConfigTreeList(
            items: value,
            emptyText: '暂无账户',
            onAddChild: _addChild,
            onEditNode: _editNode,
          ),
        ),
      ],
    );
  }
}

List _categoryItems(List groups, String direction) {
  for (final group in groups) {
    if (group is Map<String, Object?> && group['direction'] == direction) {
      final items = group['items'];
      return items is List ? items : const [];
    }
  }
  return const [];
}

class _CategoryTabView extends StatelessWidget {
  const _CategoryTabView({
    required this.items,
    required this.emptyText,
    required this.onAddRoot,
    required this.onAddChild,
    required this.onEditNode,
  });

  final Object? items;
  final String emptyText;
  final VoidCallback onAddRoot;
  final ValueChanged<String> onAddChild;
  final void Function(String nodeId, String title) onEditNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAddRoot,
              icon: const Icon(Icons.add),
              label: const Text('新增一级分类'),
            ),
          ),
        ),
        Expanded(
          child: _ConfigTreeList(
            items: items,
            emptyText: emptyText,
            onAddChild: onAddChild,
            onEditNode: onEditNode,
          ),
        ),
      ],
    );
  }
}

class _ConfigTreeList extends StatelessWidget {
  const _ConfigTreeList({
    required this.items,
    required this.emptyText,
    required this.onAddChild,
    required this.onEditNode,
  });

  final Object? items;
  final String emptyText;
  final ValueChanged<String> onAddChild;
  final void Function(String nodeId, String title) onEditNode;

  @override
  Widget build(BuildContext context) {
    final list = items is List ? items as List : const [];
    if (list.isEmpty) {
      return Center(child: Text(emptyText));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final item = list[index];
        if (item is! Map<String, Object?>) {
          return const SizedBox.shrink();
        }
        return _ConfigNodeTile(
          node: item,
          onAddChild: onAddChild,
          onEditNode: onEditNode,
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 20),
      itemCount: list.length,
    );
  }
}

class _ConfigNodeTile extends StatelessWidget {
  const _ConfigNodeTile({
    required this.node,
    required this.onAddChild,
    required this.onEditNode,
  });

  final Map<String, Object?> node;
  final ValueChanged<String> onAddChild;
  final void Function(String nodeId, String title) onEditNode;

  @override
  Widget build(BuildContext context) {
    final children = node['children'];
    final childList = _flattenConfigChildren(children);
    final title = _stringValue(node['name'], '未命名');
    final id = _stringValue(node['id'], '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onLongPress: () => onEditNode(id, title),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final child in childList)
              _ConfigChildChip(
                label: _stringValue(child['name'], '未命名'),
                onLongPress: () => onEditNode(
                  _stringValue(child['id'], ''),
                  _stringValue(child['name'], '未命名'),
                ),
              ),
            _ConfigChildChip(
              label: '添加',
              icon: Icons.add,
              isAction: true,
              onTap: () => onAddChild(id),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfigChildChip extends StatelessWidget {
  const _ConfigChildChip({
    required this.label,
    this.icon,
    this.isAction = false,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final IconData? icon;
  final bool isAction;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isAction
              ? colorScheme.primaryContainer.withValues(alpha: 0.55)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAction ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isAction ? colorScheme.primary : null,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(color: isAction ? colorScheme.primary : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Map<String, Object?>> _flattenConfigChildren(Object? value) {
  if (value is! List) {
    return const [];
  }

  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<String, Object?>) {
      continue;
    }
    result.add(item);
    result.addAll(_flattenConfigChildren(item['children']));
  }
  return result;
}

Future<_ConfigActionResult?> _showConfigActionDialog(
  BuildContext context, {
  required String title,
}) {
  return showDialog<_ConfigActionResult>(
    context: context,
    builder: (context) => _ConfigActionDialog(title: title),
  );
}

class _ConfigActionResult {
  const _ConfigActionResult.rename(this.name) : delete = false;
  const _ConfigActionResult.delete() : name = '', delete = true;

  final String name;
  final bool delete;
}

class _ConfigActionDialog extends StatefulWidget {
  const _ConfigActionDialog({required this.title});

  final String title;

  @override
  State<_ConfigActionDialog> createState() => _ConfigActionDialogState();
}

class _ConfigActionDialogState extends State<_ConfigActionDialog> {
  late final TextEditingController _controller;
  bool _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.title);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(labelText: '名称', counterText: ''),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          if (_confirmingDelete)
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.45),
                  foregroundColor: Theme.of(context).colorScheme.error,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _ConfigActionResult.delete()),
                child: const Text('相关账目也会被删除'),
              ),
            )
          else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _confirmingDelete = true;
                });
              },
              child: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            FilledButton(onPressed: _submit, child: const Text('确定')),
          ],
        ],
      ),
    );
  }

  void _submit() {
    Navigator.of(context).pop(_ConfigActionResult.rename(_controller.text));
  }
}

class _CurrencyConfigList extends StatelessWidget {
  const _CurrencyConfigList({required this.config, required this.onDelete});

  final Map<String, Object?> config;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final currencies = _enabledCurrencies(config);
    if (currencies.isEmpty) {
      return const Center(child: Text('暂无常用外币'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final currency = currencies[index];
        final code = _stringValue(currency['code'], '');
        final tile = ListTile(
          title: Text(_stringValue(currency['name'], '未命名币种')),
          subtitle: Text(code),
          trailing: Text(_currencyRateText(config, code)),
        );
        if (code == 'CNY') {
          return tile;
        }
        return _SwipeDeleteTile(
          key: ValueKey('currency_$code'),
          onDelete: () => onDelete(code),
          child: tile,
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemCount: currencies.length,
    );
  }
}

class _SwipeDeleteTile extends StatefulWidget {
  const _SwipeDeleteTile({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onDelete;

  @override
  State<_SwipeDeleteTile> createState() => _SwipeDeleteTileState();
}

class _SwipeDeleteTileState extends State<_SwipeDeleteTile> {
  static const double _deleteWidth = 80;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          setState(() {
            if (velocity < 0) {
              _revealed = true;
            } else if (velocity > 0) {
              _revealed = false;
            }
          });
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: _deleteWidth,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                      shape: const RoundedRectangleBorder(),
                    ),
                    onPressed: () {
                      setState(() {
                        _revealed = false;
                      });
                      widget.onDelete();
                    },
                    child: const Text('删除'),
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: Matrix4.translationValues(
                _revealed ? -_deleteWidth : 0,
                0,
                0,
              ),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddCurrencyPage extends StatefulWidget {
  const AddCurrencyPage({super.key, required this.config});

  final Map<String, Object?> config;

  @override
  State<AddCurrencyPage> createState() => _AddCurrencyPageState();
}

class _AddCurrencyPageState extends State<AddCurrencyPage> {
  late Map<String, Object?> _config;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _config = _jsonMapCopy(widget.config);
    _ensureAllCurrencyOptions(_config);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _searchController.text.trim().toLowerCase();
    final currencies = _allCurrencies(_config).where((currency) {
      if (keyword.isEmpty) {
        return true;
      }
      final code = _stringValue(currency['code'], '').toLowerCase();
      final name = _stringValue(currency['name'], '').toLowerCase();
      return code.contains(keyword) || name.contains(keyword);
    }).toList();

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_config);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('添加常用外币'),
          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('全选'),
                Checkbox(
                  value: _allCurrenciesSelected(),
                  onChanged: (value) => _setAllCurrenciesEnabled(value == true),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: '搜索币种或代码',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: currencies.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final currency = currencies[index];
                    final code = _stringValue(currency['code'], '');
                    final selected = currency['enabled'] != false;
                    return ListTile(
                      onTap: () => _setCurrencyEnabled(code, !selected),
                      title: Text(_stringValue(currency['name'], '未命名币种')),
                      subtitle: Text(code),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_currencyRateText(_config, code)),
                          Checkbox(
                            value: selected,
                            onChanged: (value) =>
                                _setCurrencyEnabled(code, value ?? false),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setCurrencyEnabled(String code, bool enabled) {
    setState(() {
      final currencies = _mutableList(_config['currencies']);
      for (final item in currencies) {
        if (item is Map<String, Object?> && item['code'] == code) {
          item['enabled'] = code == 'CNY' ? true : enabled;
        }
      }
      _config['currencies'] = currencies;
    });
  }

  bool _allCurrenciesSelected() {
    final currencies = _allCurrencies(_config);
    return currencies.isNotEmpty &&
        currencies.every((currency) => currency['enabled'] != false);
  }

  void _setAllCurrenciesEnabled(bool enabled) {
    setState(() {
      final currencies = _mutableList(_config['currencies']);
      for (final item in currencies) {
        if (item is Map<String, Object?>) {
          final code = _stringValue(item['code'], '');
          item['enabled'] = code == 'CNY' ? true : enabled;
        }
      }
      _config['currencies'] = currencies;
    });
  }
}

Future<Map<String, Object?>> _loadLedgerConfig(LedgerInfo ledger) async {
  final path =
      ledger.configurationPath ??
      (await LedgerConfigurationStore().configurationFile(ledger.id)).path;
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('配置文件不存在：$path');
  }
  final json = jsonDecode(await file.readAsString());
  if (json is Map<String, Object?>) {
    final normalized = _normalizeLedgerConfig(json);
    normalized['exchangeRates'] = await ExchangeRateStore().loadOrRefresh();
    if (jsonEncode(normalized) != jsonEncode(json)) {
      await file.writeAsString(jsonEncode(normalized), flush: true);
    }
    return normalized;
  }
  throw const FormatException('配置文件必须是 JSON 对象');
}

Future<void> _saveLedgerConfig(
  LedgerInfo ledger,
  Map<String, Object?> config,
) async {
  final path =
      ledger.configurationPath ??
      (await LedgerConfigurationStore().configurationFile(ledger.id)).path;
  await File(path).writeAsString(jsonEncode(config), flush: true);
}

Future<void> _recordRecentCategoryUsage(
  LedgerInfo ledger,
  Map<String, Object?> config,
  TransactionKind kind,
  _TransactionChoice choice,
) async {
  final normalized = _normalizeLedgerConfig(config);
  final recent = _recentCategoryConfig(normalized);
  final direction = _categoryDirectionKey(kind);
  final items = [
    _recentCategoryToJson(choice),
    for (final item in _mutableList(recent[direction]))
      if (item is Map<String, Object?> &&
          _stringValue(item['value'], '') != choice.value)
        item,
  ].take(8).toList();
  recent[direction] = items;
  normalized['recentCategories'] = recent;
  config
    ..clear()
    ..addAll(normalized);
  await _saveLedgerConfig(ledger, normalized);
}

Map<String, Object?> _recentCategoryConfig(Map<String, Object?> config) {
  final recent = config['recentCategories'];
  if (recent is Map<String, Object?>) {
    return Map<String, Object?>.from(recent);
  }
  return <String, Object?>{};
}

String _categoryDirectionKey(TransactionKind kind) {
  return kind == TransactionKind.income ? 'income' : 'expense';
}

Map<String, Object?> _recentCategoryToJson(_TransactionChoice choice) {
  return {
    'id': choice.id,
    'label': choice.label,
    'value': choice.value,
    if (choice.sqliteId != null) 'sqliteId': choice.sqliteId,
    if (choice.parent != null) 'parent': _recentCategoryToJson(choice.parent!),
  };
}

List<_TransactionChoice> _recentCategoryChoices(
  Map<String, Object?> config,
  TransactionKind kind,
) {
  final recent = config['recentCategories'];
  if (recent is! Map<String, Object?>) {
    return const [];
  }
  final items = _mutableList(recent[_categoryDirectionKey(kind)]);
  return [
    for (final item in items.take(8))
      if (item is Map<String, Object?>) _recentCategoryFromJson(item),
  ];
}

_TransactionChoice _recentCategoryFromJson(Map<String, Object?> item) {
  final parentJson = item['parent'];
  final parent = parentJson is Map<String, Object?>
      ? _recentCategoryFromJson(parentJson)
      : null;
  final value = _stringValue(item['value'], _stringValue(item['label'], ''));
  return _TransactionChoice(
    id: _stringValue(item['id'], value),
    label: _stringValue(item['label'], value),
    value: value,
    sqliteId: item['sqliteId'] is int ? item['sqliteId'] as int : null,
    parent: parent,
  );
}

String _categoryRecentLabel(_TransactionChoice choice) {
  return choice.value.replaceAll(' / ', ' · ');
}

class _TransactionChoice {
  const _TransactionChoice({
    required this.id,
    required this.label,
    required this.value,
    this.sqliteId,
    this.parent,
  });

  final String id;
  final String label;
  final String value;
  final int? sqliteId;
  final _TransactionChoice? parent;
}

Future<_TransactionChoice?> _showTransactionChoicePicker(
  BuildContext context, {
  required String title,
  required List<_TransactionChoice> choices,
}) {
  if (choices.isEmpty) {
    showAppSnackBar(context, '$title 暂无可选项');
    return Future.value(null);
  }
  return showDialog<_TransactionChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: choices.length,
              itemBuilder: (context, index) {
                final choice = choices[index];
                return ListTile(
                  title: Text(choice.label),
                  onTap: () => Navigator.of(context).pop(choice),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

Future<_TransactionChoice?> _showCategoryChoicePicker(
  BuildContext context, {
  required Map<String, Object?> config,
  required TransactionKind kind,
}) {
  final sections = _categoryEditSections(config, kind);
  final recent = _recentCategoryChoices(config, kind);
  if (sections.isEmpty && recent.isEmpty) {
    showAppSnackBar(context, '选择分类 暂无可选项');
    return Future.value(null);
  }
  return showDialog<_TransactionChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('选择分类'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (recent.isNotEmpty)
                  _CategoryChoiceSectionView(
                    title: '最近使用',
                    choices: recent,
                    useFullLabel: true,
                  ),
                for (final section in sections)
                  _CategoryChoiceSectionView(
                    title: section.title,
                    choices: section.choices,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

class _CategoryChoiceSectionView extends StatelessWidget {
  const _CategoryChoiceSectionView({
    required this.title,
    required this.choices,
    this.useFullLabel = false,
  });

  final String title;
  final List<_TransactionChoice> choices;
  final bool useFullLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in choices)
                ActionChip(
                  label: Text(
                    useFullLabel ? _categoryRecentLabel(choice) : choice.label,
                  ),
                  onPressed: () => Navigator.of(context).pop(choice),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryChoiceSection {
  const _CategoryChoiceSection({required this.title, required this.choices});

  final String title;
  final List<_TransactionChoice> choices;
}

List<_CategoryChoiceSection> _categoryEditSections(
  Map<String, Object?> config,
  TransactionKind kind,
) {
  final direction = kind == TransactionKind.income ? 'income' : 'expense';
  final groups = config['categories'];
  if (groups is! List) {
    return const [];
  }
  final sections = <_CategoryChoiceSection>[];
  for (final group in groups) {
    if (group is! Map<String, Object?> || group['direction'] != direction) {
      continue;
    }
    for (final item in _mutableList(group['items'])) {
      if (item is Map<String, Object?>) {
        final section = _categoryEditSection(item);
        if (section != null) {
          sections.add(section);
        }
      }
    }
  }
  return sections;
}

_CategoryChoiceSection? _categoryEditSection(Map<String, Object?> node) {
  final root = _categoryChoiceFromNode(node);
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    return _CategoryChoiceSection(title: root.label, choices: [root]);
  }
  final choices = <_TransactionChoice>[];
  for (final child in children) {
    _collectCategoryLeafChoices(child, choices, root);
  }
  return _CategoryChoiceSection(title: root.label, choices: choices);
}

_TransactionChoice _categoryChoiceFromNode(
  Map<String, Object?> node, [
  _TransactionChoice? parent,
]) {
  final name = _stringValue(node['name'], '未命名分类');
  final id = _stringValue(node['id'], '');
  final value = parent == null ? name : '${parent.value} / $name';
  return _TransactionChoice(
    id: id,
    label: name,
    value: value,
    sqliteId: _sqliteIdFromConfigId(id, 'ssj_'),
    parent: parent,
  );
}

void _collectCategoryLeafChoices(
  Map<String, Object?> node,
  List<_TransactionChoice> choices, [
  _TransactionChoice? parent,
]) {
  final choice = _categoryChoiceFromNode(node, parent);
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    choices.add(choice);
    return;
  }
  for (final child in children) {
    _collectCategoryLeafChoices(child, choices, choice);
  }
}

List<_TransactionChoice> _categoryEditChoices(
  Map<String, Object?> config,
  TransactionKind kind,
) {
  final direction = kind == TransactionKind.income ? 'income' : 'expense';
  final groups = config['categories'];
  if (groups is! List) {
    return const [];
  }
  final choices = <_TransactionChoice>[];
  for (final group in groups) {
    if (group is! Map<String, Object?> || group['direction'] != direction) {
      continue;
    }
    for (final item in _mutableList(group['items'])) {
      if (item is Map<String, Object?>) {
        _collectCategoryEditChoices(item, choices);
      }
    }
  }
  return choices;
}

void _collectCategoryEditChoices(
  Map<String, Object?> node,
  List<_TransactionChoice> choices, [
  _TransactionChoice? parent,
]) {
  final name = _stringValue(node['name'], '未命名分类');
  final id = _stringValue(node['id'], '');
  final value = parent == null ? name : '${parent.value} / $name';
  final choice = _TransactionChoice(
    id: id,
    label: value,
    value: value,
    sqliteId: _sqliteIdFromConfigId(id, 'ssj_'),
    parent: parent,
  );
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    choices.add(choice);
    return;
  }
  for (final child in children) {
    _collectCategoryEditChoices(child, choices, choice);
  }
}

List<_TransactionChoice> _accountEditChoices(Map<String, Object?> config) {
  final accounts = config['accounts'];
  if (accounts is! List) {
    return const [];
  }
  final choices = <_TransactionChoice>[];
  for (final item in accounts) {
    if (item is Map<String, Object?>) {
      _collectAccountEditChoices(item, choices);
    }
  }
  return choices;
}

void _collectAccountEditChoices(
  Map<String, Object?> node,
  List<_TransactionChoice> choices, [
  _TransactionChoice? parent,
]) {
  final name = _stringValue(node['name'], '未命名账户');
  final id = _stringValue(node['id'], '');
  final choice = _TransactionChoice(
    id: id,
    label: parent == null ? name : '${parent.label} · $name',
    value: name,
    sqliteId: _sqliteIdFromConfigId(id, 'ssj_account_'),
    parent: parent,
  );
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    choices.add(choice);
    return;
  }
  for (final child in children) {
    _collectAccountEditChoices(child, choices, choice);
  }
}

List<_TransactionChoice> _currencyEditChoices(Map<String, Object?> config) {
  return [
    for (final currency in _enabledCurrencies(config))
      _currencyEditChoice(currency),
  ];
}

_TransactionChoice _currencyEditChoice(Map<String, Object?> currency) {
  final code = _stringValue(currency['code'], '').toUpperCase();
  return _TransactionChoice(
    id: code,
    label: '${_currencyFlag(code)} $code · ${_stringValue(currency['name'], '未命名币种')}',
    value: code,
  );
}

String _currencyFlag(String code) {
  return switch (code.toUpperCase()) {
    'CNY' => '🇨🇳',
    'USD' => '🇺🇸',
    'JPY' => '🇯🇵',
    'HKD' => '🇭🇰',
    'EUR' => '🇪🇺',
    'GBP' => '🇬🇧',
    'AUD' => '🇦🇺',
    'CAD' => '🇨🇦',
    'CHF' => '🇨🇭',
    'SGD' => '🇸🇬',
    'NZD' => '🇳🇿',
    'KRW' => '🇰🇷',
    'THB' => '🇹🇭',
    'MYR' => '🇲🇾',
    'RUB' => '🇷🇺',
    'INR' => '🇮🇳',
    'BRL' => '🇧🇷',
    'ZAR' => '🇿🇦',
    _ => '¤',
  };
}

Future<void> _saveLedgerTransaction({
  required String databasePath,
  required TransactionRecord? record,
  required TransactionKind kind,
  required String amountText,
  required DateTime tradeTime,
  required _TransactionChoice category,
  required _TransactionChoice account,
  required String currencyCode,
  required String note,
}) async {
  final db = sqlite3.open(databasePath);
  var transactionStarted = false;
  try {
    db.execute('begin immediate');
    transactionStarted = true;
    _ensureTransactionSchema(db);
    final categoryId = _ensureTransactionCategory(db, category, kind);
    final accountId = _ensureTransactionAccount(db, account);
    final transactionId = int.tryParse(record?.id ?? '');
    if (record == null || transactionId == null) {
      final insertedId = _insertTransaction(
        db,
        kind: kind,
        amountText: amountText,
        tradeTime: tradeTime,
        categoryId: categoryId,
        accountId: accountId,
        note: note,
      );
      _upsertTransactionCurrency(db, insertedId, currencyCode);
    } else {
      _updateTransaction(
        db,
        transactionId: transactionId,
        kind: kind,
        amountText: amountText,
        tradeTime: tradeTime,
        categoryId: categoryId,
        accountId: accountId,
        note: note,
      );
      _upsertTransactionCurrency(db, transactionId, currencyCode);
    }
    db.execute('commit');
    transactionStarted = false;
  } catch (_) {
    if (transactionStarted) {
      db.execute('rollback');
    }
    rethrow;
  } finally {
    db.dispose();
  }
}

Future<void> _deleteLedgerTransaction(String databasePath, String recordId) async {
  final transactionId = int.tryParse(recordId);
  if (transactionId == null) {
    throw ArgumentError('流水 ID 无效：$recordId');
  }
  final db = sqlite3.open(databasePath);
  var transactionStarted = false;
  try {
    db.execute('begin immediate');
    transactionStarted = true;
    if (_sqliteTableExists(db, 't_transaction')) {
      db.execute('delete from t_transaction where transactionPOID = ?', [
        transactionId,
      ]);
    }
    if (_sqliteTableExists(db, 'app_transaction_extensions')) {
      db.execute('delete from app_transaction_extensions where transaction_id = ?', [
        recordId,
      ]);
    }
    db.execute('commit');
    transactionStarted = false;
  } catch (_) {
    if (transactionStarted) {
      db.execute('rollback');
    }
    rethrow;
  } finally {
    db.dispose();
  }
}

void _ensureTransactionSchema(Database db) {
  db.execute('''
    create table if not exists t_category (
      categoryPOID integer primary key,
      name text not null,
      parentCategoryPOID integer,
      depth integer not null default 1,
      path text,
      type integer not null default 0,
      ordered integer not null default 0,
      hidden integer not null default 0
    )
  ''');
  db.execute('''
    create table if not exists t_account (
      accountPOID integer primary key,
      name text not null,
      accountGroupPOID integer,
      ordered integer not null default 0,
      hidden integer not null default 0
    )
  ''');
  db.execute('''
    create table if not exists t_transaction (
      transactionPOID integer primary key,
      type integer not null,
      tradeTime integer not null,
      sellerCategoryPOID integer,
      sellerMoney text,
      buyerCategoryPOID integer,
      buyerMoney text,
      sellerAccountPOID integer,
      buyerAccountPOID integer,
      memo text
    )
  ''');
  _addColumnIfMissing(db, 't_transaction', 'sellerAccountPOID integer');
  _addColumnIfMissing(db, 't_transaction', 'buyerAccountPOID integer');
  _addColumnIfMissing(db, 't_transaction', 'memo text');
  db.execute('''
    create table if not exists app_transaction_extensions (
      transaction_id text primary key,
      currency_code text not null default 'CNY',
      encrypted_note integer not null default 0
    )
  ''');
}

void _addColumnIfMissing(Database db, String tableName, String definition) {
  final column = definition.split(' ').first;
  final exists = db
      .select('pragma table_info(${_quoteSqlIdentifier(tableName)})')
      .any((row) => row['name'] == column);
  if (!exists) {
    db.execute(
      'alter table ${_quoteSqlIdentifier(tableName)} add column $definition',
    );
  }
}

int _ensureTransactionCategory(
  Database db,
  _TransactionChoice choice,
  TransactionKind kind,
) {
  final id = choice.sqliteId ?? _stableAppSqliteId(choice.id, 1000000000);
  final parent = choice.parent;
  final parentId = parent == null
      ? -1
      : _ensureTransactionCategory(db, parent, kind);
  final name = choice.value.split(' / ').last;
  final type = kind == TransactionKind.income ? 1 : 0;
  final depth = parent == null ? 1 : 2;
  final path = parent == null ? '/-1/$id/' : '/-1/$parentId/$id/';
  _upsertTableRow(
    db,
    tableName: 't_category',
    primaryKeyColumn: 'categoryPOID',
    primaryKeyValue: id,
    values: {
      'name': name,
      'parentCategoryPOID': parentId,
      'depth': depth,
      'path': path,
      'type': type,
      'ordered': 0,
      'hidden': 0,
    },
  );
  return id;
}

int _ensureTransactionAccount(Database db, _TransactionChoice choice) {
  final id = choice.sqliteId ?? _stableAppSqliteId(choice.id, 2000000000);
  _upsertTableRow(
    db,
    tableName: 't_account',
    primaryKeyColumn: 'accountPOID',
    primaryKeyValue: id,
    values: {
      'name': choice.value,
      'accountGroupPOID': null,
      'ordered': 0,
      'hidden': 0,
    },
  );
  return id;
}

int _insertTransaction(
  Database db, {
  required TransactionKind kind,
  required String amountText,
  required DateTime tradeTime,
  required int categoryId,
  required int accountId,
  required String note,
}) {
  final isIncome = kind == TransactionKind.income;
  final transactionId = _nextTransactionId(db);
  final knownValues = <String, Object?>{
    'transactionPOID': transactionId,
    'type': isIncome ? 1 : 0,
    'tradeTime': tradeTime.millisecondsSinceEpoch,
    'sellerCategoryPOID': isIncome ? null : categoryId,
    'sellerMoney': isIncome ? null : amountText,
    'buyerCategoryPOID': isIncome ? categoryId : null,
    'buyerMoney': isIncome ? amountText : null,
    'sellerAccountPOID': isIncome ? null : accountId,
    'buyerAccountPOID': isIncome ? accountId : null,
    'memo': note,
  };
  final columns = <String>[];
  final values = <Object?>[];
  for (final column in _sqliteColumns(db, 't_transaction')) {
    final name = _stringValue(column['name'], '');
    if (name.isEmpty) {
      continue;
    }
    if (knownValues.containsKey(name)) {
      columns.add(name);
      values.add(knownValues[name]);
      continue;
    }
    if (column['notnull'] == 1 && column['dflt_value'] == null) {
      columns.add(name);
      values.add(_sqliteDefaultValueForColumn(name, column['type']));
    }
  }
  final placeholders = List.filled(columns.length, '?').join(', ');
  db.execute(
    '''
    insert into t_transaction(
      ${columns.map(_quoteSqlIdentifier).join(', ')}
    ) values ($placeholders)
    ''',
    values,
  );
  return transactionId;
}

int _nextTransactionId(Database db) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rows = db.select(
    'select max(cast(transactionPOID as integer)) as id from t_transaction',
  );
  final maxId = rows.isEmpty ? null : rows.first['id'] as int?;
  final candidate = maxId == null || maxId < now ? now : maxId + 1;
  return candidate <= 0 ? now : candidate;
}

void _upsertTableRow(
  Database db, {
  required String tableName,
  required String primaryKeyColumn,
  required Object primaryKeyValue,
  required Map<String, Object?> values,
}) {
  final quotedTable = _quoteSqlIdentifier(tableName);
  final quotedPrimaryKey = _quoteSqlIdentifier(primaryKeyColumn);
  final exists = db
      .select(
        'select 1 from $quotedTable where $quotedPrimaryKey = ? limit 1',
        [primaryKeyValue],
      )
      .isNotEmpty;
  if (exists) {
    final columns = {
      for (final column in _sqliteColumns(db, tableName))
        _stringValue(column['name'], ''),
    };
    final updateValues = <String, Object?>{
      for (final entry in values.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
    };
    if (updateValues.isEmpty) {
      return;
    }
    db.execute(
      '''
      update $quotedTable set
        ${updateValues.keys.map((key) => '${_quoteSqlIdentifier(key)} = ?').join(', ')}
      where $quotedPrimaryKey = ?
      ''',
      [...updateValues.values, primaryKeyValue],
    );
    return;
  }

  _insertTableRow(
    db,
    tableName: tableName,
    primaryKeyColumn: primaryKeyColumn,
    primaryKeyValue: primaryKeyValue,
    values: values,
  );
}

void _insertTableRow(
  Database db, {
  required String tableName,
  required String primaryKeyColumn,
  required Object primaryKeyValue,
  required Map<String, Object?> values,
}) {
  final insertColumns = <String>[];
  final insertValues = <Object?>[];
  for (final column in _sqliteColumns(db, tableName)) {
    final name = _stringValue(column['name'], '');
    if (name.isEmpty) {
      continue;
    }
    if (name == primaryKeyColumn) {
      insertColumns.add(name);
      insertValues.add(primaryKeyValue);
      continue;
    }
    if (values.containsKey(name)) {
      insertColumns.add(name);
      insertValues.add(values[name]);
      continue;
    }
    if (column['notnull'] == 1 && column['dflt_value'] == null) {
      insertColumns.add(name);
      insertValues.add(_sqliteDefaultValueForColumn(name, column['type']));
    }
  }
  final placeholders = List.filled(insertColumns.length, '?').join(', ');
  db.execute(
    '''
    insert into ${_quoteSqlIdentifier(tableName)}(
      ${insertColumns.map(_quoteSqlIdentifier).join(', ')}
    ) values ($placeholders)
    ''',
    insertValues,
  );
}

void _updateTransaction(
  Database db, {
  required int transactionId,
  required TransactionKind kind,
  required String amountText,
  required DateTime tradeTime,
  required int categoryId,
  required int accountId,
  required String note,
}) {
  final isIncome = kind == TransactionKind.income;
  db.execute(
    '''
    update t_transaction set
      type = ?,
      tradeTime = ?,
      sellerCategoryPOID = ?,
      sellerMoney = ?,
      buyerCategoryPOID = ?,
      buyerMoney = ?,
      sellerAccountPOID = ?,
      buyerAccountPOID = ?,
      memo = ?
    where transactionPOID = ?
    ''',
    [
      isIncome ? 1 : 0,
      tradeTime.millisecondsSinceEpoch,
      isIncome ? null : categoryId,
      isIncome ? null : amountText,
      isIncome ? categoryId : null,
      isIncome ? amountText : null,
      isIncome ? null : accountId,
      isIncome ? accountId : null,
      note,
      transactionId,
    ],
  );
}

void _upsertTransactionCurrency(
  Database db,
  int transactionId,
  String currencyCode,
) {
  db.execute(
    '''
    insert into app_transaction_extensions(transaction_id, currency_code, encrypted_note)
    values (?, ?, 0)
    on conflict(transaction_id) do update set
      currency_code = excluded.currency_code
    ''',
    [transactionId.toString(), currencyCode],
  );
}

int? _sqliteIdFromConfigId(String id, String prefix) {
  if (!id.startsWith(prefix)) {
    return null;
  }
  return int.tryParse(id.substring(prefix.length));
}

int _stableAppSqliteId(String id, int base) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return -(base + hash);
}

String _quoteSqlIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}

List<Map<String, Object?>> _sqliteColumns(Database db, String tableName) {
  return [
    for (final row in db.select(
      'pragma table_info(${_quoteSqlIdentifier(tableName)})',
    ))
      {
        'cid': row['cid'],
        'name': row['name'],
        'type': row['type'],
        'notnull': row['notnull'],
        'dflt_value': row['dflt_value'],
        'pk': row['pk'],
      },
  ];
}

Object _sqliteDefaultValueForColumn(String name, Object? type) {
  final lowerName = name.toLowerCase();
  if (lowerName.contains('time') || lowerName.endsWith('at')) {
    return DateTime.now().millisecondsSinceEpoch;
  }
  final lowerType = type?.toString().toLowerCase() ?? '';
  if (lowerType.contains('int') ||
      lowerType.contains('real') ||
      lowerType.contains('numeric') ||
      lowerType.contains('double') ||
      lowerType.contains('float')) {
    return 0;
  }
  return '';
}

Map<String, Object?> _jsonMapCopy(Map<String, Object?> value) {
  final decoded = jsonDecode(jsonEncode(value));
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  return <String, Object?>{};
}

List<Object?> _mutableList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return <Object?>[];
}

Map<String, Object?> _categoryGroup(
  Map<String, Object?> config,
  String direction,
) {
  final groups = _mutableList(config['categories']);
  for (final group in groups) {
    if (group is Map<String, Object?> && group['direction'] == direction) {
      config['categories'] = groups;
      return group;
    }
  }
  final group = <String, Object?>{'direction': direction, 'items': <Object?>[]};
  groups.add(group);
  config['categories'] = groups;
  return group;
}

Map<String, Object?> _newConfigNode(String name) {
  return {
    'id': 'app_${DateTime.now().microsecondsSinceEpoch}',
    'name': name,
    'children': <Object?>[],
  };
}

bool _containsName(List<Object?> items, String name) {
  final normalized = name.trim().toLowerCase();
  return items.any(
    (item) =>
        item is Map<String, Object?> &&
        _stringValue(item['name'], '').toLowerCase() == normalized,
  );
}

Map<String, Object?>? _findNode(Object? value, String id) {
  if (value is List) {
    for (final item in value) {
      final found = _findNode(item, id);
      if (found != null) {
        return found;
      }
    }
  }
  if (value is Map<String, Object?>) {
    if (value['id'] == id) {
      return value;
    }
    final itemsFound = _findNode(value['items'], id);
    if (itemsFound != null) {
      return itemsFound;
    }
    return _findNode(value['children'], id);
  }
  return null;
}

bool _removeNode(Object? value, String id) {
  if (value is List) {
    for (var index = 0; index < value.length; index += 1) {
      final item = value[index];
      if (item is Map<String, Object?> && item['id'] == id) {
        value.removeAt(index);
        return true;
      }
      if (_removeNode(item, id)) {
        return true;
      }
    }
  } else if (value is Map<String, Object?>) {
    return _removeNode(value['items'], id) ||
        _removeNode(value['children'], id);
  }
  return false;
}

Future<void> _deleteLedgerRowsForConfigNode({
  required Map<String, Object?> config,
  required String databasePath,
  required String section,
  required String nodeId,
}) async {
  if (!nodeId.startsWith('ssj_')) {
    return;
  }
  final dbFile = File(databasePath);
  if (!dbFile.existsSync()) {
    return;
  }
  final node = _findNode(config[section], nodeId);
  if (node == null) {
    return;
  }

  final db = sqlite3.open(databasePath);
  try {
    if (section == 'categories') {
      final ids = _collectSsjIds(node, 'ssj_');
      if (ids.isEmpty || !_sqliteTableExists(db, 't_category')) {
        return;
      }
      if (_sqliteTableExists(db, 't_transaction')) {
        _executeDeleteIn(
          db,
          'delete from t_transaction where sellerCategoryPOID in ({}) or buyerCategoryPOID in ({})',
          ids,
        );
      }
      _executeDeleteIn(
        db,
        'delete from t_category where categoryPOID in ({})',
        ids,
      );
    } else if (section == 'accounts') {
      final accountIds = _collectSsjIds(node, 'ssj_account_');
      final groupIds = _collectSsjIds(node, 'ssj_group_');
      if (accountIds.isNotEmpty && _sqliteTableExists(db, 't_transaction')) {
        _executeDeleteIn(
          db,
          'delete from t_transaction where sellerAccountPOID in ({}) or buyerAccountPOID in ({})',
          accountIds,
        );
      }
      if (accountIds.isNotEmpty && _sqliteTableExists(db, 't_account')) {
        _executeDeleteIn(
          db,
          'delete from t_account where accountPOID in ({})',
          accountIds,
        );
      }
      if (groupIds.isNotEmpty && _sqliteTableExists(db, 't_account_group')) {
        _executeDeleteIn(
          db,
          'delete from t_account_group where accountGroupPOID in ({})',
          groupIds,
        );
      }
    }
  } finally {
    db.dispose();
  }
}

Future<void> _renameLedgerConfigNode({
  required String databasePath,
  required String section,
  required String nodeId,
  required String name,
}) async {
  if (!nodeId.startsWith('ssj_')) {
    return;
  }
  final dbFile = File(databasePath);
  if (!dbFile.existsSync()) {
    return;
  }

  final db = sqlite3.open(databasePath);
  try {
    if (section == 'categories') {
      final categoryId = _ssjIdValue(nodeId, 'ssj_');
      if (categoryId == null || !_sqliteTableExists(db, 't_category')) {
        return;
      }
      db.execute('update t_category set name = ? where categoryPOID = ?', [
        name,
        categoryId,
      ]);
    } else if (section == 'accounts') {
      final accountId = _ssjIdValue(nodeId, 'ssj_account_');
      if (accountId != null && _sqliteTableExists(db, 't_account')) {
        db.execute('update t_account set name = ? where accountPOID = ?', [
          name,
          accountId,
        ]);
        return;
      }
      final groupId = _ssjIdValue(nodeId, 'ssj_group_');
      if (groupId != null && _sqliteTableExists(db, 't_account_group')) {
        db.execute(
          'update t_account_group set name = ? where accountGroupPOID = ?',
          [name, groupId],
        );
      }
    }
  } finally {
    db.dispose();
  }
}

List<int> _collectSsjIds(Map<String, Object?> node, String prefix) {
  final ids = <int>[];
  void visit(Map<String, Object?> item) {
    final id = _stringValue(item['id'], '');
    final parsed = _ssjIdValue(id, prefix);
    if (parsed != null) {
      ids.add(parsed);
    }
    for (final child in _mutableList(item['children'])) {
      if (child is Map<String, Object?>) {
        visit(child);
      }
    }
  }

  visit(node);
  return ids;
}

int? _ssjIdValue(String nodeId, String prefix) {
  if (!nodeId.startsWith(prefix)) {
    return null;
  }
  return int.tryParse(nodeId.substring(prefix.length));
}

bool _sqliteTableExists(Database db, String tableName) {
  final rows = db.select(
    "select 1 from sqlite_master where type = 'table' and name = ? limit 1",
    [tableName],
  );
  return rows.isNotEmpty;
}

void _executeDeleteIn(Database db, String sqlTemplate, List<int> ids) {
  final placeholders = List.filled(ids.length, '?').join(', ');
  final placeholderGroups = '{}'.allMatches(sqlTemplate).length;
  var sql = sqlTemplate;
  for (var i = 0; i < placeholderGroups; i += 1) {
    sql = sql.replaceFirst('{}', placeholders);
  }
  db.execute(sql, [for (var i = 0; i < placeholderGroups; i += 1) ...ids]);
}

List<Map<String, Object?>> _enabledCurrencies(Map<String, Object?> config) {
  final currencies = _allCurrencies(
    config,
  ).where((currency) => currency['enabled'] != false).toList();
  currencies.sort((a, b) {
    final aCode = _stringValue(a['code'], '');
    final bCode = _stringValue(b['code'], '');
    if (aCode == 'CNY') {
      return -1;
    }
    if (bCode == 'CNY') {
      return 1;
    }
    return aCode.compareTo(bCode);
  });
  return currencies;
}

Map<String, Object?> _normalizeLedgerConfig(Map<String, Object?> config) {
  final normalized = _jsonMapCopy(config);
  _normalizeCurrencyOptions(normalized);
  return normalized;
}

void _normalizeCurrencyOptions(Map<String, Object?> config) {
  final byCode = <String, Map<String, Object?>>{};
  for (final item in _allCurrencies(config)) {
    final code = _stringValue(item['code'], '').toUpperCase();
    if (code.isEmpty) {
      continue;
    }
    byCode[code] = {
      ...item,
      'code': code,
      'enabled': item['enabled'] ?? _defaultCurrencyCodes.contains(code),
      'isBase': code == 'CNY',
    };
  }

  for (final currency in _supportedCurrencyOptions) {
    final code = _stringValue(currency['code'], '').toUpperCase();
    byCode.putIfAbsent(
      code,
      () => {
        ...currency,
        'code': code,
        'enabled': _defaultCurrencyCodes.contains(code),
        'isBase': code == 'CNY',
      },
    );
  }

  if (config['currencySelectionMigrated'] != true) {
    for (final entry in byCode.entries) {
      entry.value['enabled'] = _defaultCurrencyCodes.contains(entry.key);
    }
    config['currencySelectionMigrated'] = true;
  }
  if (byCode.containsKey('CNY')) {
    byCode['CNY']!['enabled'] = true;
    byCode['CNY']!['isBase'] = true;
  }

  final ordered = <Map<String, Object?>>[];
  for (final code in _defaultCurrencyCodeOrder) {
    final currency = byCode.remove(code);
    if (currency != null) {
      ordered.add(currency);
    }
  }
  final rest = byCode.values.toList()
    ..sort((a, b) {
      final aCode = _stringValue(a['code'], '');
      final bCode = _stringValue(b['code'], '');
      return aCode.compareTo(bCode);
    });
  config['currencies'] = [...ordered, ...rest];
}

List<Map<String, Object?>> _allCurrencies(Map<String, Object?> config) {
  return [
    for (final item in _mutableList(config['currencies']))
      if (item is Map<String, Object?>) item,
  ];
}

void _ensureAllCurrencyOptions(Map<String, Object?> config) {
  final currencies = _mutableList(config['currencies']);
  final codes = {
    for (final item in currencies)
      if (item is Map<String, Object?>) _stringValue(item['code'], ''),
  };
  for (final currency in _supportedCurrencyOptions) {
    final code = _stringValue(currency['code'], '');
    if (!codes.contains(code)) {
      currencies.add({...currency, 'enabled': false});
    }
  }
  config['currencies'] = currencies;
}

String _currencyRateText(Map<String, Object?> config, String code) {
  if (code == 'CNY') {
    return '1.0000';
  }
  final exchangeRates = config['exchangeRates'];
  if (exchangeRates is Map<String, Object?>) {
    final rates = exchangeRates['rates'];
    if (rates is Map<String, Object?> && rates[code] != null) {
      final rate = rates[code];
      if (rate is num) {
        return rate.toStringAsFixed(4);
      }
      final parsed = double.tryParse(rate.toString());
      if (parsed != null) {
        return parsed.toStringAsFixed(4);
      }
    }
  }
  return '汇率 --';
}

const List<Map<String, Object?>> _supportedCurrencyOptions = [
  {'code': 'CNY', 'name': '人民币', 'isBase': true},
  {'code': 'USD', 'name': '美元', 'isBase': false},
  {'code': 'JPY', 'name': '日元', 'isBase': false},
  {'code': 'HKD', 'name': '港币', 'isBase': false},
  {'code': 'EUR', 'name': '欧元', 'isBase': false},
  {'code': 'GBP', 'name': '英镑', 'isBase': false},
  {'code': 'AUD', 'name': '澳元', 'isBase': false},
  {'code': 'CAD', 'name': '加拿大元', 'isBase': false},
  {'code': 'CHF', 'name': '瑞士法郎', 'isBase': false},
  {'code': 'SGD', 'name': '新加坡元', 'isBase': false},
  {'code': 'KRW', 'name': '韩元', 'isBase': false},
  {'code': 'NZD', 'name': '新西兰元', 'isBase': false},
  {'code': 'THB', 'name': '泰铢', 'isBase': false},
  {'code': 'MYR', 'name': '马来西亚林吉特', 'isBase': false},
  {'code': 'RUB', 'name': '俄罗斯卢布', 'isBase': false},
];

const List<String> _defaultCurrencyCodeOrder = [
  'CNY',
  'USD',
  'JPY',
  'HKD',
  'EUR',
  'GBP',
  'AUD',
];

const Set<String> _defaultCurrencyCodes = {
  'CNY',
  'USD',
  'JPY',
  'HKD',
  'EUR',
  'GBP',
  'AUD',
};

Future<String?> _requestConfigName(
  BuildContext context, {
  required String title,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ConfigNameDialog(title: title),
  );
}

class _ConfigNameDialog extends StatefulWidget {
  const _ConfigNameDialog({required this.title});

  final String title;

  @override
  State<_ConfigNameDialog> createState() => _ConfigNameDialogState();
}

class _ConfigNameDialogState extends State<_ConfigNameDialog> {
  late final TextEditingController _controller;

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(labelText: '名称', counterText: ''),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }
}

String _stringValue(Object? value, String fallback) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return fallback;
  }
  return text;
}

class LedgerNameDialog extends StatefulWidget {
  const LedgerNameDialog({
    super.key,
    required this.existingLedgers,
    this.initialName = '',
    this.excludedLedgerId,
    this.title = '命名账本',
    this.actionLabel = '继续',
  });

  final List<LedgerInfo> existingLedgers;
  final String initialName;
  final String? excludedLedgerId;
  final String title;
  final String actionLabel;

  @override
  State<LedgerNameDialog> createState() => _LedgerNameDialogState();
}

class _LedgerNameDialogState extends State<LedgerNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
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
        (ledger) =>
            ledger.id != widget.excludedLedgerId &&
            normalizeLedgerName(ledger.name) == normalized,
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
      title: Text(widget.title),
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
        FilledButton(onPressed: _submitName, child: Text(widget.actionLabel)),
      ],
    );
  }
}

Future<String?> _showLedgerNoteDialog(
  BuildContext context, {
  required LedgerInfo ledger,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _LedgerNoteDialog(ledger: ledger),
  );
}

class _LedgerNoteDialog extends StatefulWidget {
  const _LedgerNoteDialog({required this.ledger});

  final LedgerInfo ledger;

  @override
  State<_LedgerNoteDialog> createState() => _LedgerNoteDialogState();
}

class _LedgerNoteDialogState extends State<_LedgerNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.ledger.note);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('账本备注：${widget.ledger.name}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: '备注',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

Future<bool?> _showDeleteLedgerDialog(
  BuildContext context, {
  required LedgerInfo ledger,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('确认删除账本"${ledger.name}"？'),
      content: const Text('删除后会移除 App 管理的账本文件和配置文件。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认删除'),
        ),
      ],
    ),
  );
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

class _StartupLoadingPage extends StatelessWidget {
  const _StartupLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

class _EmptyLedgerState extends StatelessWidget {
  const _EmptyLedgerState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: Text('创建或导入一个账本开始使用。')),
    );
  }
}

class _LedgerListTile extends StatelessWidget {
  const _LedgerListTile({
    required this.ledger,
    required this.isLastOpened,
    required this.enabled,
    required this.onOpen,
    required this.onRename,
    required this.onEditNote,
    required this.onExport,
    required this.onDelete,
    required this.onPendingFeature,
  });

  final LedgerInfo ledger;
  final bool isLastOpened;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onEditNote;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final ValueChanged<String> onPendingFeature;

  @override
  Widget build(BuildContext context) {
    final exists = File(ledger.path).existsSync();
    final subtitleParts = [
      ledger.sourceKind.label,
      _formatDateTime(ledger.createdAt.toLocal()),
      exists ? '文件正常' : '文件丢失',
      if (isLastOpened) '上次打开',
      if (ledger.note.trim().isNotEmpty) '备注：${ledger.note.trim()}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: enabled && exists,
        leading: Icon(
          exists ? Icons.folder_outlined : Icons.error_outline,
          color: exists ? null : Theme.of(context).colorScheme.error,
        ),
        title: Text(ledger.name),
        subtitle: Text(subtitleParts.join(' · ')),
        onTap: enabled && exists ? onOpen : null,
        trailing: PopupMenuButton<String>(
          tooltip: '账本操作',
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
                return;
              case 'note':
                onEditNote();
                return;
              case 'export':
                onExport();
                return;
              case 'delete':
                onDelete();
                return;
              default:
                onPendingFeature(value);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'note', child: Text('编辑备注')),
            PopupMenuItem(value: 'export', child: Text('导出账本')),
            PopupMenuItem(value: 'delete', child: Text('删除账本')),
          ],
        ),
      ),
    );
  }
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
          label: const Text('从随手记本地备份导出的 KBF 文件创建'),
        ),
      ],
    );
  }
}

class _DashboardCards extends StatelessWidget {
  const _DashboardCards({required this.snapshot});

  final LedgerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month);
    final yearStart = DateTime(today.year);
    final transactions = snapshot.transactions;

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.25,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _DashboardCard.fromRecords(
          title: '今天',
          records: _recordsInRange(transactions, today, tomorrow),
        ),
        _DashboardCard.fromRecords(
          title: '本周',
          records: _recordsInRange(transactions, weekStart, tomorrow),
        ),
        _DashboardCard.fromRecords(
          title: '本月',
          records: _recordsInRange(transactions, monthStart, tomorrow),
        ),
        _DashboardCard.fromRecords(
          title: '本年',
          records: _recordsInRange(transactions, yearStart, tomorrow),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  _DashboardCard({
    required this.title,
    required Iterable<TransactionRecord> records,
  }) : income = _sum(records, TransactionKind.income),
       expense = _sum(records, TransactionKind.expense);

  _DashboardCard.fromRecords({
    required String title,
    required Iterable<TransactionRecord> records,
  }) : this(title: title, records: records);

  final String title;
  final double income;
  final double expense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleSmall),
            _AmountLine(
              label: '收入',
              amountText: '${_formatAmount(income)} 元',
              color: Colors.red.shade700,
            ),
            _AmountLine(
              label: '支出',
              amountText: '-${_formatAmount(expense)} 元',
              color: Colors.green.shade700,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amountText,
    required this.color,
  });

  final String label;
  final String amountText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: amountText,
            style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _QueryPanel extends StatelessWidget {
  const _QueryPanel({
    required this.startDate,
    required this.endDate,
    required this.includeIncome,
    required this.includeExpense,
    required this.minAmountController,
    required this.maxAmountController,
    required this.noteController,
    required this.accountLabel,
    required this.categoryLabel,
    required this.currencyLabel,
    required this.onPickAccounts,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onPickCurrencies,
    required this.onPickCategories,
    required this.onClearStartDate,
    required this.onClearEndDate,
    required this.onIncludeIncomeChanged,
    required this.onIncludeExpenseChanged,
    required this.onReset,
    required this.onQuery,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final bool includeIncome;
  final bool includeExpense;
  final TextEditingController minAmountController;
  final TextEditingController maxAmountController;
  final TextEditingController noteController;
  final String accountLabel;
  final String categoryLabel;
  final String currencyLabel;
  final VoidCallback onPickAccounts;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final VoidCallback onPickCurrencies;
  final VoidCallback onPickCategories;
  final VoidCallback onClearStartDate;
  final VoidCallback onClearEndDate;
  final ValueChanged<bool> onIncludeIncomeChanged;
  final ValueChanged<bool> onIncludeExpenseChanged;
  final VoidCallback onReset;
  final VoidCallback? onQuery;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterField(
                  label: '账户',
                  value: accountLabel,
                  onPressed: onPickAccounts,
                ),
                _DateFilterField(
                  label: '开始时间',
                  value: startDate == null ? '全部' : _formatDate(startDate!),
                  onTap: onPickStartDate,
                  onClear: startDate == null ? null : onClearStartDate,
                ),
                _DateFilterField(
                  label: '结束时间',
                  value: endDate == null ? '全部' : _formatDate(endDate!),
                  onTap: onPickEndDate,
                  onClear: endDate == null ? null : onClearEndDate,
                ),
                _FilterField(
                  label: '币种',
                  value: currencyLabel,
                  onPressed: onPickCurrencies,
                ),
                _FilterField(
                  label: '分类',
                  value: categoryLabel,
                  onPressed: onPickCategories,
                ),
                _CompactCheckbox(
                  label: '收入',
                  value: includeIncome,
                  onChanged: onIncludeIncomeChanged,
                ),
                _CompactCheckbox(
                  label: '支出',
                  value: includeExpense,
                  onChanged: onIncludeExpenseChanged,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minAmountController,
                    decoration: const InputDecoration(
                      labelText: '最低金额',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: maxAmountController,
                    decoration: const InputDecoration(
                      labelText: '最高金额',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: '备注关键字',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onQuery?.call(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReset,
                    child: const Text('重置筛选规则'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onQuery,
                    child: const Text('查询'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactCheckbox extends StatelessWidget {
  const _CompactCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      showCheckmark: true,
      onSelected: onChanged,
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InputChip(label: Text('$label：$value'), onPressed: onPressed);
  }
}

class _DateFilterField extends StatelessWidget {
  const _DateFilterField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text('$label：$value'),
      onPressed: onTap,
      onDeleted: onClear,
    );
  }
}

class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({
    required this.ledger,
    required this.snapshot,
    this.title,
    this.subtitle,
    this.scrollController,
    this.loadingMore = false,
    this.onRecordTap,
  });

  final LedgerInfo ledger;
  final LedgerSnapshot snapshot;
  final String? title;
  final String? subtitle;
  final ScrollController? scrollController;
  final bool loadingMore;
  final ValueChanged<TransactionRecord>? onRecordTap;

  @override
  Widget build(BuildContext context) {
    final transactions = snapshot.transactions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title ??
              (snapshot.hasSuiShouJiTables
                  ? '已读取 ${transactions.length} 条最近流水'
                  : '空白账本已创建'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle ?? '${ledger.sourceKind.label} · ${ledger.path}',
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
              controller: scrollController,
              itemCount: transactions.length + (loadingMore ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index >= transactions.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _TransactionTile(
                  record: transactions[index],
                  onTap: onRecordTap == null
                      ? null
                      : () => onRecordTap!(transactions[index]),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  _TransactionTile({required this.record, this.onTap});

  final TransactionRecord record;
  final VoidCallback? onTap;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final isIncome = record.kind == TransactionKind.income;
    final amountColor = isIncome ? Colors.red.shade700 : Colors.green.shade700;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(record.categoryPath),
      subtitle: Text(_transactionSubtitle(record, _dateFormat)),
      onTap: onTap,
      trailing: Text(
        '${isIncome ? '+' : '-'}${record.amount} ${record.currencyCode}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _transactionSubtitle(TransactionRecord record, DateFormat dateFormat) {
  final note = record.note?.trim();
  final parts = [
    dateFormat.format(record.tradeTime),
    if (record.accountName != null && record.accountName!.isNotEmpty)
      record.accountName!,
    if (note != null && note.isNotEmpty) note,
  ];
  return parts.join(' · ');
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

String _formatDateTime(DateTime dateTime) {
  return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
}

String _formatDate(DateTime dateTime) {
  return DateFormat('yyyy-MM-dd').format(dateTime);
}

String _exportLedgerFileName(LedgerInfo ledger) {
  final safeName = ledger.name
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final name = safeName.isEmpty ? '账本' : safeName;
  return '${name}_$timestamp.sqlite';
}

String _querySummary(TransactionQuery query) {
  final startText = query.startDate == null
      ? '不限'
      : _formatDate(query.startDate!);
  final endText = query.endDate == null
      ? '不限'
      : _formatDate(query.endDate!.subtract(const Duration(days: 1)));
  final minAmountText = query.minAmount?.toStringAsFixed(2) ?? '不限';
  final maxAmountText = query.maxAmount?.toStringAsFixed(2) ?? '不限';
  final parts = <String>[
    if (query.startDate == null && query.endDate == null)
      '时间全部'
    else
      '时间 $startText 至 $endText',
    if (query.includeIncome && query.includeExpense)
      '收入和支出'
    else if (query.includeIncome)
      '仅收入'
    else if (query.includeExpense)
      '仅支出',
    if (query.minAmount == null && query.maxAmount == null)
      '金额全部'
    else
      '金额 $minAmountText 至 $maxAmountText',
    if (query.noteKeyword != null && query.noteKeyword!.isNotEmpty)
      '备注：${query.noteKeyword}',
    if (query.accountNames != null) '账户 ${query.accountNames!.length} 项',
    if (query.currencyCodes != null) '币种 ${query.currencyCodes!.join(',')}',
    if (query.categoryPaths != null) '分类 ${query.categoryPaths!.length} 项',
  ];
  return parts.join(' · ');
}

String _filterLabel(Set<String>? selected) {
  if (selected == null) {
    return '全部';
  }
  if (selected.isEmpty) {
    return '未选择';
  }
  return '${selected.length} 项';
}

Set<String>? _intersectSelection(
  Set<String>? selected,
  List<_FilterOption> options,
) {
  if (selected == null) {
    return null;
  }
  return _normalizedFilterSelection(selected, options);
}

Set<String>? _normalizedFilterSelection(
  Set<String> selected,
  List<_FilterOption> options,
) {
  final values = {for (final option in options) option.value};
  final kept = selected.intersection(values);
  if (kept.length == values.length) {
    return null;
  }
  return kept;
}

class _FilterOption {
  const _FilterOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _FilterTreeNode {
  const _FilterTreeNode({
    required this.label,
    required this.values,
    this.children = const [],
  });

  final String label;
  final Set<String> values;
  final List<_FilterTreeNode> children;
}

Future<Set<String>?> _showMultiSelectFilter(
  BuildContext context, {
  required String title,
  required List<_FilterOption> options,
  required Set<String>? selectedValues,
}) {
  if (options.isEmpty) {
    showAppSnackBar(context, '$title 暂无可选项');
    return Future.value(null);
  }
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => _MultiSelectFilterDialog(
      title: title,
      options: options,
      selectedValues:
          selectedValues ?? {for (final option in options) option.value},
    ),
  );
}

Future<Set<String>?> _showTreeMultiSelectFilter(
  BuildContext context, {
  required String title,
  required List<_FilterTreeNode> nodes,
  required List<_FilterOption> options,
  required Set<String>? selectedValues,
}) {
  if (options.isEmpty || nodes.isEmpty) {
    showAppSnackBar(context, '$title 暂无可选项');
    return Future.value(null);
  }
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => _TreeMultiSelectFilterDialog(
      title: title,
      nodes: nodes,
      allValues: {for (final option in options) option.value},
      selectedValues:
          selectedValues ?? {for (final option in options) option.value},
    ),
  );
}

class _MultiSelectFilterDialog extends StatefulWidget {
  const _MultiSelectFilterDialog({
    required this.title,
    required this.options,
    required this.selectedValues,
  });

  final String title;
  final List<_FilterOption> options;
  final Set<String> selectedValues;

  @override
  State<_MultiSelectFilterDialog> createState() =>
      _MultiSelectFilterDialogState();
}

class _MultiSelectFilterDialogState extends State<_MultiSelectFilterDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selectedValues};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            CheckboxListTile(
              value: _selected.length == widget.options.length,
              onChanged: (value) {
                setState(() {
                  _selected
                    ..clear()
                    ..addAll(
                      value == true
                          ? widget.options.map((option) => option.value)
                          : const <String>[],
                    );
                });
              },
              title: const Text('全选'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 1),
            for (final option in widget.options)
              CheckboxListTile(
                value: _selected.contains(option.value),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selected.add(option.value);
                    } else {
                      _selected.remove(option.value);
                    }
                  });
                },
                title: Text(option.label),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _TreeMultiSelectFilterDialog extends StatefulWidget {
  const _TreeMultiSelectFilterDialog({
    required this.title,
    required this.nodes,
    required this.allValues,
    required this.selectedValues,
  });

  final String title;
  final List<_FilterTreeNode> nodes;
  final Set<String> allValues;
  final Set<String> selectedValues;

  @override
  State<_TreeMultiSelectFilterDialog> createState() =>
      _TreeMultiSelectFilterDialogState();
}

class _TreeMultiSelectFilterDialogState
    extends State<_TreeMultiSelectFilterDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selectedValues};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            _FilterCheckboxRow(
              label: '全选',
              value: _checkboxValue(widget.allValues),
              onChanged: (_) {
                final shouldSelect = _checkboxValue(widget.allValues) != true;
                setState(() {
                  _selected
                    ..clear()
                    ..addAll(
                      shouldSelect ? widget.allValues : const <String>{},
                    );
                });
              },
            ),
            const Divider(height: 1),
            for (final node in widget.nodes) ...[
              _FilterCheckboxRow(
                label: node.label,
                value: _checkboxValue(node.values),
                onChanged: (_) => _setValues(
                  node.values,
                  _checkboxValue(node.values) != true,
                ),
              ),
              for (final child in node.children)
                _FilterCheckboxRow(
                  label: child.label,
                  indent: 28,
                  value: _checkboxValue(child.values),
                  onChanged: (_) => _setValues(
                    child.values,
                    _checkboxValue(child.values) != true,
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('确定'),
        ),
      ],
    );
  }

  bool? _checkboxValue(Set<String> values) {
    if (values.isEmpty) {
      return false;
    }
    final selectedCount = values.where(_selected.contains).length;
    if (selectedCount == 0) {
      return false;
    }
    if (selectedCount == values.length) {
      return true;
    }
    return null;
  }

  void _setValues(Set<String> values, bool selected) {
    setState(() {
      if (selected) {
        _selected.addAll(values);
      } else {
        _selected.removeAll(values);
      }
    });
  }
}

class _FilterCheckboxRow extends StatelessWidget {
  const _FilterCheckboxRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.indent = 0,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value == true ? false : true),
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: 4, top: 2, bottom: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              tristate: true,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: onChanged,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

List<_FilterTreeNode> _categoryFilterTree(Map<String, Object?>? config) {
  final categories = config?['categories'];
  if (categories is! List) {
    return const [];
  }
  final nodes = <_FilterTreeNode>[];
  for (final group in categories) {
    if (group is! Map<String, Object?>) {
      continue;
    }
    final direction = group['direction'] == 'income' ? '收入' : '支出';
    for (final item in _mutableList(group['items'])) {
      if (item is Map<String, Object?>) {
        nodes.add(_categoryFilterTreeNode(item, direction));
      }
    }
  }
  return nodes.where((node) => node.values.isNotEmpty).toList();
}

_FilterTreeNode _categoryFilterTreeNode(
  Map<String, Object?> node,
  String direction,
) {
  final name = _stringValue(node['name'], '未命名分类');
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    return _FilterTreeNode(label: '$direction · $name', values: {name});
  }

  final childNodes = <_FilterTreeNode>[];
  for (final child in children) {
    childNodes.addAll(_categoryLeafFilterNodes(child, name));
  }
  return _FilterTreeNode(
    label: '$direction · $name',
    values: {for (final child in childNodes) ...child.values},
    children: childNodes,
  );
}

List<_FilterTreeNode> _categoryLeafFilterNodes(
  Map<String, Object?> node,
  String parentName,
) {
  final name = _stringValue(node['name'], '未命名分类');
  final path = '$parentName / $name';
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    return [
      _FilterTreeNode(label: name, values: {path}),
    ];
  }
  return [
    for (final child in children) ..._categoryLeafFilterNodes(child, path),
  ];
}

List<_FilterOption> _categoryFilterOptions(Map<String, Object?>? config) {
  final categories = config?['categories'];
  if (categories is! List) {
    return const [];
  }
  final options = <_FilterOption>[];
  for (final group in categories) {
    if (group is! Map<String, Object?>) {
      continue;
    }
    final direction = group['direction'] == 'income' ? '收入' : '支出';
    for (final item in _mutableList(group['items'])) {
      if (item is Map<String, Object?>) {
        _collectCategoryOptions(item, direction, options);
      }
    }
  }
  return options;
}

void _collectCategoryOptions(
  Map<String, Object?> node,
  String direction,
  List<_FilterOption> options, [
  String? parentName,
]) {
  final name = _stringValue(node['name'], '');
  final path = parentName == null ? name : '$parentName / $name';
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    options.add(_FilterOption(value: path, label: '$direction · $path'));
  } else {
    for (final child in children) {
      _collectCategoryOptions(child, direction, options, path);
    }
  }
}

List<_FilterOption> _accountFilterOptions(Map<String, Object?>? config) {
  final accounts = config?['accounts'];
  if (accounts is! List) {
    return const [];
  }
  final options = <_FilterOption>[];
  for (final item in accounts) {
    if (item is Map<String, Object?>) {
      _collectAccountOptions(item, options);
    }
  }
  return options;
}

List<_FilterTreeNode> _accountFilterTree(Map<String, Object?>? config) {
  final accounts = config?['accounts'];
  if (accounts is! List) {
    return const [];
  }
  final nodes = <_FilterTreeNode>[];
  for (final item in accounts) {
    if (item is Map<String, Object?>) {
      nodes.add(_accountFilterTreeNode(item));
    }
  }
  return nodes.where((node) => node.values.isNotEmpty).toList();
}

_FilterTreeNode _accountFilterTreeNode(Map<String, Object?> node) {
  final name = _stringValue(node['name'], '未命名账户');
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    return _FilterTreeNode(label: name, values: {name});
  }

  final childNodes = <_FilterTreeNode>[];
  for (final child in children) {
    childNodes.addAll(_accountLeafFilterNodes(child));
  }
  return _FilterTreeNode(
    label: name,
    values: {for (final child in childNodes) ...child.values},
    children: childNodes,
  );
}

List<_FilterTreeNode> _accountLeafFilterNodes(Map<String, Object?> node) {
  final name = _stringValue(node['name'], '未命名账户');
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    return [
      _FilterTreeNode(label: name, values: {name}),
    ];
  }
  return [for (final child in children) ..._accountLeafFilterNodes(child)];
}

void _collectAccountOptions(
  Map<String, Object?> node,
  List<_FilterOption> options, [
  String? parentName,
]) {
  final name = _stringValue(node['name'], '');
  final children = [
    for (final child in _mutableList(node['children']))
      if (child is Map<String, Object?>) child,
  ];
  if (children.isEmpty) {
    options.add(
      _FilterOption(
        value: name,
        label: parentName == null ? name : '$parentName · $name',
      ),
    );
  } else {
    for (final child in children) {
      _collectAccountOptions(child, options, name);
    }
  }
}

List<_FilterOption> _currencyFilterOptions(Map<String, Object?>? config) {
  if (config == null) {
    return const [];
  }
  return [
    for (final currency in _enabledCurrencies(config))
      _FilterOption(
        value: _stringValue(currency['code'], ''),
        label:
            '${_stringValue(currency['code'], '')} · ${_stringValue(currency['name'], '未命名币种')}',
      ),
  ];
}

double _sum(Iterable<TransactionRecord> records, TransactionKind kind) {
  return records
      .where((record) => record.kind == kind)
      .fold<double>(0, (sum, record) => sum + double.parse(record.amount));
}

Iterable<TransactionRecord> _recordsInRange(
  Iterable<TransactionRecord> records,
  DateTime start,
  DateTime end,
) {
  return records.where((record) {
    final tradeDate = record.tradeTime;
    return !tradeDate.isBefore(start) && tradeDate.isBefore(end);
  });
}

String _formatAmount(double amount) => amount.toStringAsFixed(2);

void _showPendingFeature(BuildContext context, String featureName) {
  showAppSnackBar(context, '$featureName 将在后续迭代实现');
}
