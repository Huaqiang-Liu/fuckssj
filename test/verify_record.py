from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import tempfile
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from scripts.verify_backup import (  # noqa: E402
    ordered_recovery_candidates,
    read_candidates,
    restore_sqlite_header,
    validate_sqlite,
)


RECORD_SQL_TEMPLATE = """
select
    t.transactionPOID,
    t.type,
    t.tradeTime,
    case
        when t.type = 0 then 'expense'
        when t.type = 1 then 'income'
        else 'other'
    end as kind,
    cast(case
        when t.type = 1 then t.buyerMoney
        else t.sellerMoney
    end as text) as amount,
    c.categoryPOID as category_id,
    case
        when c.depth <= 1 or p.categoryPOID is null then c.name
        else p.name
    end as first_category,
    case
        when c.depth <= 1 or p.categoryPOID is null then null
        else c.name
    end as second_category,
    c.depth as category_depth,
    c.path as category_path
from t_transaction t
left join t_category c
    on c.categoryPOID = case
        when t.type = 1 then t.buyerCategoryPOID
        else t.sellerCategoryPOID
    end
left join t_category p
    on p.categoryPOID = c.parentCategoryPOID
where t.type in (0, 1)
order by t.tradeTime {direction}, t.transactionPOID {direction}
limit 1
"""


def default_input() -> Path:
    backups = sorted(ROOT.glob("*.kbf"))
    if backups:
        return backups[0]

    recovered = ROOT / "recovered" / "mymoney.sqlite"
    if recovered.exists():
        return recovered

    raise FileNotFoundError(
        "No .kbf backup found in the repository root and no recovered/mymoney.sqlite found"
    )


def load_sqlite_from_backup(path: Path) -> bytes:
    candidates = read_candidates(path)
    for candidate in ordered_recovery_candidates(candidates):
        restored = restore_sqlite_header(candidate.data)
        if validate_sqlite(restored).get("ok"):
            return restored
    raise RuntimeError(f"No recoverable SQLite database found in {path}")


def query_record(database: bytes, order: str) -> dict[str, object]:
    direction = "desc" if order == "latest" else "asc"
    with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as fp:
        fp.write(database)
        tmp_name = fp.name

    tmp_path = Path(tmp_name)
    conn: sqlite3.Connection | None = None
    try:
        conn = sqlite3.connect(tmp_path)
        conn.row_factory = sqlite3.Row
        row = conn.execute(RECORD_SQL_TEMPLATE.format(direction=direction)).fetchone()
        if row is None:
            raise RuntimeError("No income or expense record found in t_transaction")

        result = dict(row)
        result["trade_time"] = datetime.fromtimestamp(
            result["tradeTime"] / 1000
        ).strftime("%Y-%m-%d %H:%M:%S")
        return result
    finally:
        if conn is not None:
            conn.close()
        tmp_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify an income/expense record from a recovered SuiShouJi database."
    )
    parser.add_argument(
        "input",
        nargs="?",
        type=Path,
        help="Path to a .kbf backup or recovered SQLite database. Defaults to .kbf, then recovered/mymoney.sqlite.",
    )
    parser.add_argument(
        "--order",
        choices=("latest", "earliest"),
        default="latest",
        help="Select the latest or earliest income/expense record.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    args = parser.parse_args()

    input_path = args.input or default_input()
    record = query_record(load_sqlite_from_backup(input_path), args.order)

    if args.json:
        print(json.dumps(record, ensure_ascii=False, indent=2))
    else:
        print(f"kind: {record['kind']}")
        print(f"first_category: {record['first_category']}")
        print(f"second_category: {record['second_category'] or ''}")
        print(f"trade_time: {record['trade_time']}")
        print(f"amount: {record['amount']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
