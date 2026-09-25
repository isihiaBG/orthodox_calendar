#!/bin/bash
# Превежда ЦЕЛИЯ том, докрай, без надзор.
#
# ⚠⚠ ИМЕНАТА НА ПРОМЕНЛИВИТЕ СА НА ЛАТИНИЦА. Кирилско име в bash дава
# „not a valid identifier" и скриптът умира на първия ред — платено вече
# веднъж при пасхалния конвейер и повторено тук.
#
# ⚠⚠ ПРЕВОДАЧЪТ Е ВЪЗОБНОВИМ — дял с готов файл в work/translated/ се
# прескача. Затова цикълът просто го вика наново: прекъсната връзка или
# убит процес струват само едно повторение.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
LOG="$ROOT/work/translate.log"
TR="$ROOT/../lives_plus/scripts/02_translate_deepseek.py"

total=$(ls "$ROOT/work/units"/*.json 2>/dev/null | wc -l)
echo "тръгва: $(date '+%H:%M:%S') | дялове: $total" >> "$LOG"
for round in $(seq 1 40); do
  done_n=$(ls "$ROOT/work/translated"/*.json 2>/dev/null | wc -l)
  echo "=== кръг $round: готови $done_n от $total ($(date '+%H:%M:%S')) ===" >> "$LOG"
  if [ "$done_n" -ge "$total" ]; then
    echo "ВСИЧКО Е ПРЕВЕДЕНО ($done_n от $total)" >> "$LOG"
    break
  fi
  python3 "$TR" --root "$ROOT" --workers 4 >> "$LOG" 2>&1
  sleep 20
done
ls "$ROOT/work/translated"/*.json 2>/dev/null | wc -l > "$ROOT/work/translate.done"
echo "край: $(date '+%H:%M:%S')" >> "$LOG"
