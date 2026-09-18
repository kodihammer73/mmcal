"""Builds assets/mmcal_symbols.json from the per-market security lists.

The source of truth is the set of CSV files in `assets/`, one per market
(``ListOfSecuritiesMalaysia.csv``, ``ListOfSecuritiesHongKong.csv``, ...). Each
row is ``code,name``; some markets ship codes only (Indonesia, Thailand, USA).

Whenever you receive a fresh list for any market, drop it in `assets/`, then run:

    python tools/build_symbols.py

The emitted JSON is what the app bundles and what gets published at
https://gurdwarasahibmelaka.com/data/mmcal_symbols.json - a per-market currency
+ Yahoo Finance exchange-suffix map, plus a flat symbol list tagged with its
market (the market tag is required because codes such as 5 and BP exist in
several markets).

The script is deliberately forgiving: header rows, padding and the quirks of the
current files are normalised here rather than in the CSVs, and it prints a
per-market report so a fresh file can be eyeballed.

Data quirks handled
-------------------
* Header rows are skipped if a future file brings one back.
* Singapore pads codes/names and prefixes some names with "$".
* Names containing commas are re-joined; trailing empty columns are dropped.
* Thailand appends the Yahoo ".BK" suffix; index rows ("^SET.BK") are dropped.
* Japan writes codes with a stray trailing zero ("7203.0" -> "72030").
* Codes that are not alphanumeric ("-") and the placeholder "0" are dropped.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
from datetime import date

# Market -> (settlement currency, Yahoo Finance exchange suffix).
# Market names must match the engine's names exactly.
MARKET_META = {
    'Malaysia': ('MYR', '.KL'),
    'Singapore': ('SGD', '.SI'),
    'Hong Kong': ('HKD', '.HK'),
    'United States (US)': ('USD', ''),
    'Thailand': ('THB', '.BK'),
    'Indonesia': ('IDR', '.JK'),
    'United Kingdom (UK)': ('GBP', '.L'),
    'Australia': ('AUD', '.AX'),
    'Japan': ('JPY', '.T'),
    'Canada': ('CAD', '.TO'),
    'Germany': ('EUR', '.DE'),
}

# assets/ filename -> engine market name. Anything else in the folder is
# ignored, so unrelated CSVs can sit next to these safely.
FILE_TO_MARKET = {
    'ListOfSecuritiesMalaysia.csv': 'Malaysia',
    'ListOfSecuritiesSingapore.csv': 'Singapore',
    'ListOfSecuritiesHongKong.csv': 'Hong Kong',
    'ListOfSecuritiesUSA.csv': 'United States (US)',
    'ListOfSecuritiesThailand.csv': 'Thailand',
    'ListOfSecuritiesIndonesia.csv': 'Indonesia',
    'ListOfSecuritiesUK.csv': 'United Kingdom (UK)',
    'ListOfSecuritiesAustralia.csv': 'Australia',
    'ListOfSecuritiesJapan.csv': 'Japan',
    'ListOfSecuritiesCanada.csv': 'Canada',
    'ListOfSecuritiesEUR.csv': 'Germany',
}

# A row whose first field is one of these is a header, not data.
HEADER_LABELS = {
    'code',
    'stock code',
    'asx code',
    'name',
    'company name',
    'name of securities',
    'short name',
    'stock_code',
    'short_name',
}

SCHEMA_VERSION = 1

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, 'assets')
OUT_PATH = os.path.join(ASSETS, 'mmcal_symbols.json')


def clean_code(market: str, raw: str) -> str:
    """Normalises one code column value for [market]."""
    code = ' '.join(raw.strip().split())
    if market == 'Thailand' and code.upper().endswith('.BK'):
        # The Thai list carries the Yahoo suffix; the app stores local codes.
        code = code[:-3].strip()
    if market == 'Japan' and len(code) == 5 and code.endswith('0'):
        # Japan's export writes "7203.0" as "72030" - recover the real code.
        code = code[:-1]
    return code.upper()


def clean_name(raw: str) -> str:
    """Normalises the remaining columns of a row into a display name."""
    name = raw.strip().rstrip(',').strip()
    if name.startswith('$'):
        # Singapore prefixes a handful of names with "$".
        name = name[1:].strip()
    return name.upper()


def usable_code(code: str) -> bool:
    """False for index rows, placeholders and punctuation-only codes."""
    if not code:
        return False
    if code.startswith('^'):  # index row
        return False
    if code == '0':  # placeholder seen in the Japan list
        return False
    return any(ch.isalnum() for ch in code)


def read_market(path: str, market: str, report: dict) -> list[tuple[str, str]]:
    """Returns the deduplicated (code, name) rows found in [path]."""
    found: dict[str, str] = {}
    order: list[str] = []
    duplicates = 0
    skipped = 0
    fixed = 0

    with open(path, newline='', encoding='utf-8-sig') as fh:
        for row in csv.reader(fh):
            if not row or not row[0].strip():
                continue
            if row[0].strip().lower() in HEADER_LABELS:
                continue

            raw_code = row[0].strip()
            code = clean_code(market, raw_code)
            if code != raw_code.upper():
                fixed += 1
            if not usable_code(code):
                skipped += 1
                continue

            name = clean_name(','.join(row[1:])) if len(row) > 1 else ''

            if code in found:
                duplicates += 1
                # Prefer a row that actually carries a name.
                if not found[code] and name:
                    found[code] = name
                continue
            found[code] = name
            order.append(code)

    report['rows'] = len(order)
    report['duplicates'] = duplicates
    report['skipped'] = skipped
    report['fixed'] = fixed
    return [(code, found[code]) for code in order]


def build(assets: str = ASSETS, quiet: bool = False) -> dict:
    """Merges every known CSV in [assets] into one dictionary document."""
    symbols: list[dict[str, str]] = []
    report: dict[str, dict] = {}

    for filename, market in FILE_TO_MARKET.items():
        path = os.path.join(assets, filename)
        entry = {'rows': 0, 'duplicates': 0, 'skipped': 0, 'fixed': 0}
        report[market] = entry
        if not os.path.exists(path):
            entry['missing'] = True
            print(f'WARNING: {filename} not found - no symbols for {market}')
            continue
        for code, name in read_market(path, market, entry):
            symbols.append({'m': market, 'c': code, 'n': name})

    if not quiet:
        print(f'{"market":<22}{"rows":>7}{"dupes":>7}{"skipped":>9}{"fixed":>7}')
        for market in MARKET_META:
            e = report[market]
            if e.get('missing'):
                print(f'{market:<22}{"MISSING":>7}')
                continue
            print(f'{market:<22}{e["rows"]:>7}{e["duplicates"]:>7}'
                  f'{e["skipped"]:>9}{e["fixed"]:>7}')

    return {
        'version': SCHEMA_VERSION,
        'updated': date.today().isoformat(),
        'markets': {
            m: {'currency': currency, 'suffix': suffix}
            for m, (currency, suffix) in MARKET_META.items()
        },
        'symbols': symbols,
    }


def write_json(doc: dict, path: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        # Compact: ~41k rows ship inside the app and are downloaded by devices.
        json.dump(doc, fh, ensure_ascii=False, separators=(',', ':'))
        fh.write('\n')


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Rebuild assets/mmcal_symbols.json from assets/*.csv')
    parser.add_argument('--out', metavar='PATH',
                        help='also copy the JSON here (e.g. for upload)')
    parser.add_argument('--quiet', action='store_true',
                        help='suppress the per-market report')
    args = parser.parse_args()

    doc = build(quiet=args.quiet)
    write_json(doc, OUT_PATH)
    print(f'Wrote {len(doc["symbols"])} symbols to {OUT_PATH}')

    if args.out:
        out = os.path.abspath(args.out)
        write_json(doc, out)
        print(f'Copied {len(doc["symbols"])} symbols to {out}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())