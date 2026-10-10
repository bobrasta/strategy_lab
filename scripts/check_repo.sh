#!/usr/bin/env bash
# Repo hygiene: the git index (= what the next commit contains) must never hold run outputs,
# build trees, market data CSVs or per-M1 equity files, and .gitignore must keep ignoring them.
# Run by the pre-commit hook (.githooks/pre-commit) and by the test suite. Prints every problem
# and exits 1 if there is any. The same script lives in hummer-engine and strategy_lab.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

max_kb=${CHECK_MAX_FILE_KB:-5120} # any single file; GitHub warns at 50 MB and refuses 100 MB
max_csv_kb=1024                    # a CSV fixture bigger than this is data, not a test fixture
fail=0
bad() {
  echo "check_repo: $*" >&2
  fail=1
}

# 1. .gitignore ignores them (probe paths; they need not exist).
for p in runs/x/equity.csv sub/runs/x/run.json build/release/hummer sub/build/x.o \
  xauusd_m1_2021-01-01_2026-10-08.csv data/xauusd_m15_2021-01-01_2026-10-08.csv equity.csv out/equity.csv; do
  git check-ignore -q --no-index "$p" || bad ".gitignore does not ignore $p"
done

# 2. Nothing of the kind is in the index.
while read -r size path; do
  name=${path##*/}
  case "/$path" in
    */runs/*) bad "run output in the index: $path" ;;
    */build/*) bad "build output in the index: $path" ;;
  esac
  case "$name" in
    equity*.csv) bad "equity file in the index: $path" ;;
    xauusd_*.csv | *_m1_*.csv | *_m5_*.csv | *_m15_*.csv | *_h1_*.csv) bad "market data in the index: $path" ;;
    *.csv) ((size > max_csv_kb * 1024)) && bad "CSV over ${max_csv_kb} KB in the index: $path ($((size / 1024)) KB)" ;;
  esac
  ((size > max_kb * 1024)) && bad "file over ${max_kb} KB in the index: $path ($((size / 1024)) KB)"
done < <(git ls-files -s | awk -F'\t' '{ split($1, a, " "); print a[2] " " $2 }' | git cat-file --batch-check='%(objectsize) %(rest)')

if ((fail)); then
  echo "check_repo: FAILED. Unstage these files (git rm --cached <path>) and keep the patterns in .gitignore." >&2
  exit 1
fi
echo "check_repo: OK ($(git ls-files | wc -l) files in the index)"
