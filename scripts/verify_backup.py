from __future__ import annotations

import argparse
import hashlib
import json
import math
import sqlite3
import struct
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path


SQLITE_HEADER = b"SQLite format 3\x00"
SQLCIPHER_PAGE_SIZE = 4096


@dataclass
class Candidate:
    name: str
    data: bytes


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = [0] * 256
    for byte in data:
        counts[byte] += 1
    total = len(data)
    value = 0.0
    for count in counts:
        if count:
            p = count / total
            value -= p * math.log2(p)
    return value


def read_candidates(path: Path) -> list[Candidate]:
    raw = path.read_bytes()
    candidates = [Candidate(path.name, raw)]

    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                if info.is_dir():
                    continue
                candidates.append(Candidate(info.filename, archive.read(info)))

    return candidates


def sqlite_probe(data: bytes) -> dict[str, object]:
    result: dict[str, object] = {
        "size": len(data),
        "sha256": sha256(data),
        "starts_with_sqlite_header": data.startswith(SQLITE_HEADER),
        "first_256_entropy": round(entropy(data[:256]), 4),
    }

    if data.startswith(SQLITE_HEADER):
        result["page_size"] = struct.unpack(">H", data[16:18])[0]
        with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as fp:
            fp.write(data)
            tmp_name = fp.name
        tmp_path = Path(tmp_name)
        try:
            with sqlite3.connect(tmp_path) as conn:
                rows = conn.execute(
                    "select name, type from sqlite_master order by type, name limit 25"
                ).fetchall()
            result["sqlite_opened"] = True
            result["sqlite_master_sample"] = rows
        except sqlite3.DatabaseError as exc:
            result["sqlite_opened"] = False
            result["sqlite_error"] = str(exc)
        finally:
            tmp_path.unlink(missing_ok=True)
    else:
        # SQLCipher databases normally do not expose the SQLite header. A high
        # entropy first page is a useful quick signal before trying keys.
        result["sqlcipher_like"] = len(data) >= SQLCIPHER_PAGE_SIZE and entropy(
            data[:SQLCIPHER_PAGE_SIZE]
        ) > 7.5

    return result


def restore_sqlite_header(data: bytes) -> bytes:
    restored = bytearray(data)
    restored[: len(SQLITE_HEADER)] = SQLITE_HEADER
    return bytes(restored)


def validate_sqlite(data: bytes) -> dict[str, object]:
    with tempfile.NamedTemporaryFile(suffix=".sqlite", delete=False) as fp:
        fp.write(data)
        tmp_name = fp.name

    tmp_path = Path(tmp_name)
    conn: sqlite3.Connection | None = None
    try:
        conn = sqlite3.connect(tmp_path)
        integrity = conn.execute("pragma integrity_check").fetchone()
        objects = conn.execute(
            "select type, count(*) from sqlite_master group by type order by type"
        ).fetchall()
        sample = conn.execute(
            "select name, type from sqlite_master order by type, name limit 25"
        ).fetchall()
        return {
            "ok": integrity == ("ok",),
            "integrity_check": integrity[0] if integrity else None,
            "sqlite_master_counts": objects,
            "sqlite_master_sample": sample,
        }
    except sqlite3.DatabaseError as exc:
        return {"ok": False, "error": str(exc)}
    finally:
        if conn is not None:
            conn.close()
        tmp_path.unlink(missing_ok=True)


def find_mymoney(candidates: list[Candidate]) -> Candidate | None:
    for candidate in candidates:
        if Path(candidate.name).name == "mymoney.sqlite":
            return candidate
    return None


def ordered_recovery_candidates(candidates: list[Candidate]) -> list[Candidate]:
    mymoney = find_mymoney(candidates)
    if mymoney is None:
        return candidates
    return [mymoney, *[candidate for candidate in candidates if candidate is not mymoney]]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inspect SuiShouJi backup files and test whether they contain readable SQLite data."
    )
    parser.add_argument("backup", type=Path, help="Path to a .kbf/.kdf backup file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write the repaired SQLite database to this path when recovery succeeds",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    args = parser.parse_args()

    candidates = read_candidates(args.backup)
    report = {
        "input": str(args.backup),
        "is_zip": zipfile.is_zipfile(args.backup),
        "entries": [{"name": c.name, **sqlite_probe(c.data)} for c in candidates],
        "recovery": None,
    }

    for candidate in ordered_recovery_candidates(candidates):
        restored = restore_sqlite_header(candidate.data)
        validation = validate_sqlite(restored)
        if validation.get("ok"):
            report["recovery"] = {
                "source_entry": candidate.name,
                "method": "replace first 16 bytes with SQLite format 3\\0",
                **validation,
            }
            if args.output:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_bytes(restored)
                report["recovery"]["output"] = str(args.output)
            break

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"input: {report['input']}")
        print(f"is_zip: {report['is_zip']}")
        for entry in report["entries"]:
            print()
            print(f"[{entry['name']}]")
            for key, value in entry.items():
                if key != "name":
                    print(f"{key}: {value}")
        print()
        print("[recovery]")
        print(report["recovery"])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
