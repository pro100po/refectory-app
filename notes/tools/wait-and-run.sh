#!/bin/bash
# Ждёт, пока наблюдатель освободится от команд других веток, шлёт run из своей ветки и ждёт ответа.
cd /home/user/refectory-app || exit 1
ME=claude/wonderful-albattani-yssc32
others_idle() {
  git fetch -q origin "+refs/heads/claude/*:refs/remotes/origin/claude/*" 2>/dev/null || return 1
  for ref in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin/claude/); do
    [ "$ref" = "origin/$ME" ] && continue
    cmd=$(git show "$ref:bridge/cmd.txt" 2>/dev/null | head -1 | tr -d '\r'); [ -z "$cmd" ] && continue
    st=$(git show "$ref:bridge/result/status.txt" 2>/dev/null | head -1 | tr -d '\r')
    cid=${cmd%% *}; sid=${st%% *}; sst=${st#* }
    if [ "$cid" != "$sid" ]; then echo "занято: $ref ($cmd; ответ: ${st:-нет})"; return 1; fi
    case "$sst" in accepted|rejected|error*) ;; *) echo "занято: $ref ждёт проверки ($st)"; return 1;; esac
  done
  return 0
}
until others_idle >/tmp/bridge-wait.state; do sleep 30; done
ID=$(date -u -d '+3 hours' '+%Y%m%d-%H%M')
echo "$ID run" > bridge/cmd.txt
git add bridge/cmd.txt && git commit -q -m "bridge: $ID run — исправление знака сдвига стены" && git push -q origin "$ME" 2>/dev/null || { echo "PUSH FAILED"; exit 2; }
echo "отправлено: $ID run в $(date -u '+%T UTC')"
sleep 90
for i in $(seq 1 120); do
  git fetch -q origin "+refs/heads/$ME:refs/remotes/origin/$ME" 2>/dev/null
  st=$(git show "origin/$ME:bridge/result/status.txt" 2>/dev/null | head -1 | tr -d '\r')
  case "$st" in "$ID "*) echo "ответ: $st в $(date -u '+%T UTC')"; exit 0;; esac
  sleep 30
done
echo "нет ответа за ~60 мин на $ID"; exit 3
