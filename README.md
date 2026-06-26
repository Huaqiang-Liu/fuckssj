# fuckssj

Tools for inspecting and converting SuiShouJi backup files.

This repository intentionally ignores local backup/database files such as
`*.kbf`, `*.sqlite`, and `*.db`, because they may contain personal financial
data.

## Current Finding

The tested `*.kbf` backup is a ZIP archive containing `mymoney.sqlite` and
`backup_info`. The embedded `mymoney.sqlite` is not SQLCipher-encrypted in the
tested sample. Its first 16 bytes are modified; replacing those bytes with the
standard SQLite header `SQLite format 3\0` produces a valid SQLite database.

## Usage

```powershell
python .\scripts\verify_backup.py path\to\backup.kbf -o recovered\mymoney.sqlite
```

The script also tries the same recovery method on direct, non-ZIP inputs such
as a raw modified SQLite file.

To verify the latest income or expense record from a local backup:

```powershell
python .\test\verify_latest_record.py
```

The script prints:

- `kind`: `expense` or `income`
- `first_category`: the top-level category
- `second_category`: the child category, when present
- `trade_time`: the ledger time formatted as `YYYY-MM-DD HH:MM:SS`
- `amount`: the income or expense amount

## SQLite Structure

The recovered database stores normal ledger rows in `t_transaction` and
categories in `t_category`.

`t_transaction` is the transaction table. The fields used by the current
verifier are:

- `transactionPOID`: primary key for the transaction.
- `type`: transaction direction. In the tested database, `0` means expense and
  `1` means income.
- `tradeTime`: ledger time as a Unix timestamp in milliseconds.
- `sellerCategoryPOID`: expense category id for `type = 0` rows.
- `sellerMoney`: expense amount for `type = 0` rows.
- `buyerCategoryPOID`: income category id for `type = 1` rows.
- `buyerMoney`: income amount for `type = 1` rows.
- `createdTime` and `modifiedTime`: row creation/update times, also stored as
  Unix timestamps in milliseconds.

`t_category` is the category table. The fields used by the current verifier
are:

- `categoryPOID`: primary key for the category.
- `name`: category display name.
- `parentCategoryPOID`: parent category id. This links a second-level category
  to its first-level category.
- `depth`: hierarchy depth. In the tested database, normal first-level
  categories use `depth = 1`; normal second-level categories use `depth = 2`.
- `path`: materialized category path, for example
  `/-1/<first-level-id>/<second-level-id>/`.
- `type`: category direction. In the tested database, `0` is expense and `1`
  is income.

To read the latest income or expense record:

1. Select rows from `t_transaction` where `type in (0, 1)`.
2. Sort by `tradeTime desc, transactionPOID desc`.
3. For an expense row, use `sellerCategoryPOID` and `sellerMoney`.
4. For an income row, use `buyerCategoryPOID` and `buyerMoney`.
5. Join the selected category id to `t_category.categoryPOID`.
6. Join `t_category.parentCategoryPOID` back to `t_category.categoryPOID` to get
   the first-level parent category when the selected category is second-level.
