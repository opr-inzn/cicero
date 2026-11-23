#!/bin/bash
# Checks before a merge: the tests, then the performance probes on this Mac's fonts, compared with the last saved
# baseline. The tests stay out of the public repository, so a clone without them has nothing to check.
#   scripts/check.sh            tests and probes
#   scripts/check.sh --quick    tests only
#   scripts/check.sh --save     also saves the probes' times as the new baseline (after a change you accept)
#   scripts/check.sh --app      also the app performance run on the small library (Tests/E2E/app-perf, a few minutes)
# Exit 0: all well. 1: a test failed. 2: a probe is slower than the baseline (median over 25 % and 2 ms more); run it
# again before believing it, the Mac may have been busy.
set -uo pipefail
cd "$(dirname "$0")/.."
QUICK= SAVE= APP=
for arg in "$@"; do
    case $arg in
        --quick) QUICK=1 ;;
        --save) SAVE=1 ;;
        --app) APP=1 ;;
        *) echo "unknown option $arg"; exit 64 ;;
    esac
done
[[ -d Tests/CiceroCoreTests ]] || { echo "No tests here (they stay out of the public repository)."; exit 0; }

OUT=$(mktemp -d)
echo "== Tests"
if ! swift test >"$OUT/tests.txt" 2>&1; then
    grep -E "✘|error:" "$OUT/tests.txt" | head -30
    echo "FAIL: tests (full output: $OUT/tests.txt)"
    exit 1
fi
grep -E "Test run with" "$OUT/tests.txt" | tail -1
[[ -n "$QUICK" ]] && exit 0

echo "== Performance probes (release build, about two minutes)"
BASELINE=Tests/E2E/perf-probes/baseline.txt
PROBES=$OUT/probes.txt
{
    echo "# $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources || echo +dirty), $(date), load $(sysctl -n vm.loadavg | tr -d '{}')"
} >"$PROBES"
if ! CICERO_PERF=all CICERO_PERF_OUT="$PROBES" swift test -c release -Xswiftc -enable-testing --filter PerfProbes >"$OUT/probes-run.txt" 2>&1; then
    tail -20 "$OUT/probes-run.txt"
    echo "FAIL: the probes didn't run (full output: $OUT/probes-run.txt)"
    exit 1
fi
STATUS=0
if [[ -f "$BASELINE" ]]; then
    python3 -I - "$BASELINE" "$PROBES" <<'EOF' || STATUS=2
import re, sys
line = re.compile(r"^perf (\S+) · (.*?): median ([\d.]+) ms")
def medians(path):
    out = {}
    for text in open(path):
        m = line.match(text)
        if m:
            out[(m[1], m[2])] = float(m[3])
    return out
old, new = medians(sys.argv[1]), medians(sys.argv[2])
slower = []
print(f"{'probe':<70} {'before':>9} {'now':>9}")
for key, now in new.items():
    was = old.get(key)
    mark = ""
    if was is None:
        mark = "  new"
    elif now - was > 2 and now > was * 1.25:
        mark = "  SLOWER"
        slower.append(key)
    elif was - now > 2 and now < was / 1.25:
        mark = "  faster"
    name = f"{key[0]} {key[1]}"[:70]
    print(f"{name:<70} {'' if was is None else f'{was:9.2f}':>9} {now:9.2f}{mark}")
sys.exit(1 if slower else 0)
EOF
else
    echo "No baseline yet: run with --save to make one."
fi
if [[ -n "$SAVE" ]]; then
    cp "$PROBES" "$BASELINE"
    echo "Saved the baseline: $BASELINE"
fi

if [[ -n "$APP" ]]; then
    echo "== App performance (small library, one warm launch)"
    PROFILES=small RUNS="warm" Tests/E2E/app-perf/run.sh || STATUS=1
fi
[[ $STATUS == 2 ]] && echo "SLOWER: a probe is slower than the baseline. Run again before believing it."
exit $STATUS
