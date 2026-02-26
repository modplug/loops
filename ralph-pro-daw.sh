#!/bin/bash
# Ralph: Parallel orchestrator for Pro DAW PRD #144
# Launches 3 worktree loops: PDC engine, audio analysis, track UI
# Usage: ./ralph-pro-daw.sh <iterations-per-loop>
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations-per-loop>"
  exit 1
fi

echo "=== Ralph Parallel Orchestrator: Pro DAW ==="
echo "PRD #144: Engine Robustness, Audio Tools & Professional UX"
echo "Iterations per loop: $1"
echo ""
echo "Launching 3 parallel worktree loops..."
echo ""

# Launch PDC & Engine (3 issues: #145, #146, #147)
./ralph-pdc-engine.sh "$1" 2>&1 | tee ralph-pdc-engine.log &
PID1=$!
echo "Started pdc-engine (PID: $PID1) — #145 PDC, #146 Low-Latency, #147 Test Suite"

# Launch Audio Analysis & UI Polish (5 issues: #148-#152)
./ralph-audio-analysis.sh "$1" 2>&1 | tee ralph-audio-analysis.log &
PID2=$!
echo "Started audio-analysis-ui (PID: $PID2) — #148-#152 Transients, Piano Roll, Info Pane"

# Launch Track UI & Tools (5 issues: #153-#157)
./ralph-track-ui.sh "$1" 2>&1 | tee ralph-track-ui.log &
PID3=$!
echo "Started track-ui-tools (PID: $PID3) — #153-#157 Headers, Freeze, Clip Gain, LUFS"

echo ""
echo "All loops running. Monitor progress:"
echo "  tail -f progress-pdc-engine.txt"
echo "  tail -f progress-audio-analysis-ui.txt"
echo "  tail -f progress-track-ui-tools.txt"
echo ""
echo "Or monitor logs:"
echo "  tail -f ralph-pdc-engine.log"
echo "  tail -f ralph-audio-analysis.log"
echo "  tail -f ralph-track-ui.log"
echo ""

# Wait for all to finish
wait $PID1
STATUS1=$?

wait $PID2
STATUS2=$?

wait $PID3
STATUS3=$?

echo ""
echo "=== All Ralph loops finished ==="
echo "pdc-engine:       exit code $STATUS1"
echo "audio-analysis:   exit code $STATUS2"
echo "track-ui-tools:   exit code $STATUS3"
echo ""
echo "Next steps:"
echo "1. Check worktree branches: git branch"
echo "2. Merge each into main:"
echo "   git checkout main"
echo "   git merge <worktree-branch-1>"
echo "   git merge <worktree-branch-2>"
echo "   git merge <worktree-branch-3>"
echo "3. Run quality gates: swift build && swift test && swiftlint"
echo "4. Manual QA: see tasks/qa-pro-daw.md"
