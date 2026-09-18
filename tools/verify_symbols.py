"""Verifies assets/mmcal_symbols.json against Yahoo Finance.

The dictionary is built from the per-market exchange exports in `assets/`, so
its codes are the exchanges' own; the short names are whatever the exports
carry (and some markets publish codes only). This script looks up every row on
Yahoo and reports, per row:

  OK       the symbol resolved and the name matches
  NAME?    the symbol resolved but Yahoo's name differs (candidate correction)
  MISSING  the symbol did not resolve on that exchange

Run it on a machine with internet access:

    python tools/verify_symbols.py                      # whole dictionary
    python tools/verify_symbols.py --market Malaysia    # one market
    python tools/verify_symbols.py --limit 25           # first 25 rows
    python tools/verify_symbols.py --fix                # also write suggestions

With --fix the corrections are written to tools/mmcal_symbols.suggested.json
for you to review - this script never edits the dictionary in place. The full
dictionary is ~41,000 rows, so a complete run is a long one: use --market or
--limit for spot checks.
"""
from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

# Market -> Yahoo Finance exchange suffix. Keep in step with build_symbols.py.
SUFFIXES = {
    'Malaysia': '.KL',
    'Singapore': '.SI',
    'Hong Kong': '.HK',
    'United States (US)': '',
    'Thailand': '.BK',
    'Indonesia': '.JK',
    'United Kingdom (UK)': '.L',
    'Australia': '.AX',
    'Japan': '.T',
    'Canada': '.TO',
    'Germany': '.DE',
}

SEARCH_URL = 'https://query1.finance.yahoo.com/v1/finance/search'
USER_AGENT = 'Mozilla/5.0'

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
JSON_PATH = os.path.join(ROOT, 'assets', 'mmcal_symbols.json')
FIXED_PATH = os.path.join(HERE, 'mmcal_symbols.suggested.json')

OK, NAME, MISSING, ERROR = 'OK', 'NAME?', 'MISSING', 'ERROR'


def normalise(value: str) -> str:
    """Matches the app's normalisation closely enough for comparison."""
    return ' '.join(value.strip().upper().split()).rstrip('.')


def lookup(code: str, suffix: str, timeout: float = 6.0) -> list:
    """Returns the raw Yahoo quote dicts for a code+suffix query."""
    query = code + suffix
    url = SEARCH_URL + '?' + urllib.parse.urlencode(
        {'q': query, 'quotesCount': 10, 'newsCount': 0,
         'lang': 'en-US', 'region': 'US'}
    )
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode('utf-8', 'replace'))
    quotes = payload.get('quotes')
    return quotes if isinstance(quotes, list) else []


def _verify_once(row: dict, delay: float) -> tuple:
    """Returns (status, yahoo_symbol, yahoo_name_or_reason)."""
    market = (row.get('market') or '').strip()
    code = (row.get('stock_code') or '').strip()
    name = (row.get('short_name') or '').strip()

    if market not in SUFFIXES:
        return ERROR, '', 'unknown market'
    if not code:
        return ERROR, '', 'no code'

    suffix = SUFFIXES[market]
    # UK tickers carry a trailing dot locally (RR.) that Yahoo omits (RR.L).
    base = code.rstrip('.') or code
    expected = (base + suffix).upper()
    # Yahoo spells share classes with a hyphen (BRK.B -> BRK-B) in both the
    # query and the result, so try both spellings.
    accepted = {expected, expected.replace('.', '-')}

    failure = ''
    for query_code in dict.fromkeys([base, base.replace('.', '-')]):
        time.sleep(delay)
        try:
            quotes = lookup(query_code, suffix)
        except urllib.error.HTTPError as exc:
            failure = f'HTTP {exc.code}'
            continue
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            failure = type(exc).__name__
            continue

        for quote in quotes:
            if not isinstance(quote, dict):
                continue
            symbol = str(quote.get('symbol') or '').upper()
            if symbol not in accepted:
                continue
            yahoo_name = str(
                quote.get('shortname') or quote.get('longname') or ''
            ).strip()
            if not yahoo_name:
                return OK, symbol, 'matched (Yahoo has no name)'
            if not normalise(name):
                # Code-only market: Yahoo's name is itself the suggestion.
                return OK, symbol, yahoo_name
            if normalise(yahoo_name) == normalise(name):
                return OK, symbol, yahoo_name
            return NAME, symbol, yahoo_name

    if failure:
        return ERROR, '', failure
    return MISSING, '', f'no quote for {expected}'


def verify_row(row: dict, delay: float, retries: int = 2) -> tuple:
    """As `_verify_once`, but retries a MISSING result.

    Yahoo's search endpoint is intermittently flaky - it returns nothing for a
    symbol that is definitely listed - so a single miss is not trustworthy.
    Observed: 5 of 6 first-pass misses resolved on the very next attempt.
    """
    result = _verify_once(row, delay)
    attempt = 0
    while result[0] == MISSING and attempt < retries:
        attempt += 1
        time.sleep(0.6)
        result = _verify_once(row, delay)
    if result[0] == MISSING and attempt:
        return MISSING, result[1], f'{result[2]} (after {attempt + 1} tries)'
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Verify mmcal_symbols.json')
    parser.add_argument('--json', default=JSON_PATH)
    parser.add_argument('--market', default=None, help='only this market')
    parser.add_argument('--limit', type=int, default=0,
                        help='only the first N rows')
    parser.add_argument('--delay', type=float, default=0.4,
                        help='seconds between requests (be kind to Yahoo)')
    parser.add_argument('--retries', type=int, default=2,
                        help='retries for a MISSING result (Yahoo is flaky)')
    parser.add_argument('--fix', action='store_true',
                        help='write tools/mmcal_symbols.suggested.json')
    args = parser.parse_args(argv)

    with open(args.json, encoding='utf-8') as handle:
        doc = json.load(handle)
    symbols = doc.get('symbols') if isinstance(doc, dict) else None
    if not isinstance(symbols, list):
        print('No symbols found - run tools/build_symbols.py first.')
        return 1

    # The verifier works on market / stock_code / short_name triples.
    rows = [
        {'market': str(row.get('m') or '').strip(),
         'stock_code': str(row.get('c') or '').strip(),
         'short_name': str(row.get('n') or '').strip()}
        for row in symbols if isinstance(row, dict)
    ]
    rows = [r for r in rows if r['market']]

    if args.market:
        rows = [r for r in rows if r['market'].strip() == args.market]
    if args.limit:
        rows = rows[: args.limit]
    if not rows:
        print('No rows to check.')
        return 1

    fixed = []
    counts = {OK: 0, NAME: 0, MISSING: 0, ERROR: 0}

    print(f'Checking {len(rows)} row(s)...\n')
    for row in rows:
        status, symbol, detail = verify_row(row, args.delay, args.retries)
        counts[status] += 1
        merged = dict(row)
        if status == NAME:
            merged['short_name'] = detail
        fixed.append(merged)
        print(f'  {status:<8} {row["market"]:<18} {row["stock_code"]:<6} '
              f'{row["short_name"]:<26} {detail}')

    print('\n' + '=' * 74)
    print(f'  OK {counts[OK]} | NAME differs {counts[NAME]} | '
          f'MISSING {counts[MISSING]} | ERROR {counts[ERROR]}')
    print('=' * 74)

    if counts[MISSING] or counts[ERROR]:
        print('\nMISSING/ERROR rows need a human decision: the code may be wrong '
              'or renamed, or Yahoo may not cover that exchange.')

    if args.fix:
        suggested = {
            'version': doc.get('version', 1),
            'updated': doc.get('updated', ''),
            'markets': doc.get('markets', {}),
            'symbols': [
                {'m': row['market'], 'c': row['stock_code'],
                 'n': row['short_name'].upper()}
                for row in fixed
            ],
        }
        with open(FIXED_PATH, 'w', encoding='utf-8', newline='\n') as handle:
            json.dump(suggested, handle, ensure_ascii=False,
                      separators=(',', ':'))
            handle.write('\n')
        scope = ('every row' if not (args.market or args.limit)
                 else 'ONLY the rows just checked')
        print(f'\nWrote {FIXED_PATH} ({scope}) - review it, then correct the '
              'source CSV(s) in assets/ and re-run build_symbols.py.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
