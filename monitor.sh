#!/bin/bash
PID=$1
if [ -z "$PID" ]; then echo "Usage: $0 <PID>"; exit 1; fi

echo "=== CView_v2 종합 모니터링 (PID: $PID) ==="
echo ""
echo "시간      | CPU%   | 상태       | RAM(MB) | 메모리상태 | 네트워크 | FD"
echo "----------|--------|-----------|---------|----------|---------|----"

PREV_RSS=0
while kill -0 "$PID" 2>/dev/null; do
  CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ')
  RSS=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ')
  RSS_MB=$(echo "scale=1; ${RSS:-0}/1024" | bc)
  SOCK=$(lsof -p "$PID" 2>/dev/null | grep -c "IPv" || echo 0)
  FD=$(lsof -p "$PID" 2>/dev/null | wc -l | tr -d ' ')
  TS=$(date '+%H:%M:%S')

  CPU_INT=$(printf "%.0f" "$CPU" 2>/dev/null || echo 0)
  RSS_INT=$(printf "%.0f" "$RSS_MB" 2>/dev/null || echo 0)

  if [ "$CPU_INT" -gt 80 ] 2>/dev/null; then
    ALERT="HIGH-CPU"
  elif [ "$CPU_INT" -gt 60 ] 2>/dev/null; then
    ALERT="ELEVATED"
  else
    ALERT="NORMAL"
  fi

  if [ "$RSS_INT" -gt 1500 ] 2>/dev/null; then
    MEM_ST="HIGH-MEM"
  elif [ "$RSS_INT" -gt 1000 ] 2>/dev/null; then
    MEM_ST="ELEVATED"
  else
    MEM_ST="OK"
  fi

  # Memory leak detection
  if [ "$PREV_RSS" -gt 0 ] 2>/dev/null; then
    DIFF=$((RSS_INT - PREV_RSS))
    if [ "$DIFF" -gt 100 ] 2>/dev/null; then
      MEM_ST="LEAK?+${DIFF}MB"
    fi
  fi
  PREV_RSS=$RSS_INT

  printf "[%s] | %5s%% | %-9s | %7s | %-8s | %4s | %s\n" \
    "$TS" "$CPU" "$ALERT" "$RSS_MB" "$MEM_ST" "$SOCK" "$FD"
  sleep 3
done

echo ""
echo "[$(date '+%H:%M:%S')] PROCESS TERMINATED!"
