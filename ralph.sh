#!/usr/bin/env bash
# 랄프 루프 (연습용)
# 사용법: ./ralph.sh <과제폴더> [최대반복=20] [agent=claude|codex]
# 예:     ./ralph.sh 01-todo-cli 20 claude
#         PUSH=1 ./ralph.sh 02-shorturl 50 claude   # 끝나면 원격에 push
#
# - <과제폴더>/PROMPT.md 를 매 반복마다 에이전트에 넣는다
# - <과제폴더>/verify.sh 가 있으면 매 반복 후 실행, exit 0 이면 종료
# - 로그는 logs/<과제폴더>-<시작시각>/ 아래에 반복별로 저장

set -uo pipefail

TASK_DIR="${1:?과제 폴더를 지정하세요 (예: 01-todo-cli)}"
MAX_ITER="${2:-20}"
AGENT="${3:-claude}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_PATH="$ROOT/$TASK_DIR"
PROMPT_FILE="$TASK_PATH/PROMPT.md"
VERIFY="$TASK_PATH/verify.sh"
LOG_DIR="$ROOT/logs/${TASK_DIR}-$(date +%m%d-%H%M)"

[[ -f "$PROMPT_FILE" ]] || { echo "PROMPT.md 없음: $PROMPT_FILE"; exit 1; }
mkdir -p "$LOG_DIR"
cd "$TASK_PATH"

run_agent() {
  case "$AGENT" in
    claude) claude -p --dangerously-skip-permissions < "$PROMPT_FILE" ;;
    codex)  codex exec --full-auto "$(cat "$PROMPT_FILE")" ;;
    *) echo "알 수 없는 agent: $AGENT"; exit 1 ;;
  esac
}

START=$(date +%s)
echo "▶ 시작: $TASK_DIR / agent=$AGENT / 최대 $MAX_ITER회 / 로그: $LOG_DIR"

for ((i=1; i<=MAX_ITER; i++)); do
  LOG="$LOG_DIR/iter-$(printf '%02d' "$i").log"
  echo "── 반복 $i/$MAX_ITER ($(date +%H:%M:%S))" | tee -a "$LOG_DIR/summary.log"

  run_agent 2>&1 | tee "$LOG"

  # 반복마다 작업 상태를 커밋해서 히스토리로 남김
  git -C "$ROOT" add -A "$TASK_DIR" >/dev/null 2>&1
  git -C "$ROOT" commit -qm "ralph($TASK_DIR): iter $i" >/dev/null 2>&1 \
    && echo "   커밋됨" | tee -a "$LOG_DIR/summary.log"

  if [[ -x "$VERIFY" ]]; then
    if "$VERIFY" > "$LOG_DIR/verify-$(printf '%02d' "$i").log" 2>&1; then
      echo "✅ verify 통과 — 반복 $i 에서 종료" | tee -a "$LOG_DIR/summary.log"
      break
    else
      echo "   ❌ verify 실패 (verify-$(printf '%02d' "$i").log 참고)" | tee -a "$LOG_DIR/summary.log"
    fi
  fi
done

ELAPSED=$(( $(date +%s) - START ))
echo "■ 종료: 총 $((ELAPSED/60))분 $((ELAPSED%60))초, 반복 $((i>MAX_ITER ? MAX_ITER : i))회" | tee -a "$LOG_DIR/summary.log"

# PUSH=1 로 실행하면 끝난 뒤 원격에 push (다른 기기에서 결과 확인용)
if [[ "${PUSH:-0}" == "1" ]]; then
  git -C "$ROOT" push -q && echo "⬆ push 완료" || echo "⚠ push 실패 (수동으로 git push 하세요)"
fi
