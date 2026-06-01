#!/usr/bin/env bash
# fulldemo.sh - run the full presentation sequence end to end.
#
# Order:
#   1. test-isolation.sh        (ADR-001 / QA1: kill BU1's DB, prove BU2 stays up)
#   2. demo-breaker.sh          (ADR-004 / QA1: break a BU's ERP, watch the circuit breaker)
#   3. demo-search-fallback.sh  (ADR-005 / QA4: pause Meilisearch, watch the DB fallback)
#   4. demo-outbox.sh           (ADR-003 / QA5: pause the CRM consumer, watch the queue drain)
#
# A 3-second pause is inserted between each step.
#
# Usage: ./scripts/fulldemo.sh
# Prerequisites: full stack up (docker compose up -d --build) and ./scripts/install-nop.sh run.
# Tip: open Grafana at http://localhost:3000/d/northstar-adr-evidence before starting.

set -uo pipefail

# Resolve this script's directory so the sub-scripts are found regardless of where you run from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GAP=3  # seconds between steps

STEPS=(
    "test-isolation.sh"
    "demo-breaker.sh"
    "demo-search-fallback.sh"
    "demo-outbox.sh"
)

banner () {
    echo
    echo "================================================================================"
    echo ">> $1"
    echo "================================================================================"
    echo
}

run_step () {
    local script="$1"
    local path="${SCRIPT_DIR}/${script}"
    if [[ ! -x "$path" ]]; then
        if [[ -f "$path" ]]; then
            bash "$path"
        else
            echo "SKIP: ${script} not found at ${path}"
            return 1
        fi
    else
        "$path"
    fi
}

echo "=== FULL DEMO: isolation + three failure-mode demos ==="
echo "Open Grafana now: http://localhost:3000/d/northstar-adr-evidence (Last 5 min, 5s refresh)"

total=${#STEPS[@]}
i=0
declare -a RESULTS=()

for script in "${STEPS[@]}"; do
    i=$((i + 1))
    banner "Step ${i}/${total}: ${script}"
    if run_step "$script"; then
        RESULTS+=("OK   ${script}")
    else
        RESULTS+=("FAIL ${script}")
        echo "!! ${script} exited non-zero (continuing so the rest of the demo still runs)"
    fi

    # 3-second break between steps (not after the last one).
    if [[ $i -lt $total ]]; then
        echo
        echo "... ${GAP}s break before the next step ..."
        sleep "$GAP"
    fi
done

echo
echo "================================================================================"
echo ">> FULL DEMO COMPLETE - summary"
echo "================================================================================"
for line in "${RESULTS[@]}"; do
    echo "   $line"
done
