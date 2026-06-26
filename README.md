# fuckssj

Tools for inspecting and converting SuiShouJi backup files.

This repository intentionally ignores local backup/database files such as
`*.kbf`, `*.kdf`, `*.sqlite`, and `*.db`, because they may contain personal
financial data.

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
as `*.kdf`.
