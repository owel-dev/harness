#!/usr/bin/env bash
# PreToolUse(Bash) hook: git push 전에 크리덴셜이 섞인 커밋이 없는지 검사한다.
#
# 검사 대상은 아직 어느 원격에도 없는 커밋이다 (--branches --tags --not --remotes).
#   1. 크리덴셜로 보이는 파일이 추가되었는지 (파일명 검사)
#   2. 커밋 내용에 비밀 값이 있는지 (gitleaks)
# 하나라도 걸리면 푸시를 막는다 (exit 2).
# gitleaks 오탐은 저장소의 .gitleaksignore나 줄 끝 `gitleaks:allow` 주석으로 제외한다.

set -o pipefail
. "$(dirname "$0")/lib/common.sh"

read_hook_input
has_git_subcommand push || exit 0
root=$(resolve_repo_root) || exit 0

LOG_OPTS='--branches --tags --not --remotes'
CRED_FILE_RE='(^|/)(\.env(\.[^/]+)?|id_(rsa|dsa|ecdsa|ed25519)|[^/]+\.(p12|pfx|jks|keystore|ppk)|\.netrc|\.pgpass|\.aws/credentials|[^/]*service[-_]?account[^/]*\.json|client_secret[^/]*\.json)$'
CRED_FILE_ALLOW_RE='(^|/)\.env\.(example|sample|template|dist)$'

# shellcheck disable=SC2086 # LOG_OPTS는 여러 옵션으로 나뉘어야 한다
[ "$(git -C "$root" rev-list --count $LOG_OPTS)" -gt 0 ] || exit 0

problems=""

# shellcheck disable=SC2086
files=$(git -C "$root" log $LOG_OPTS --no-renames --diff-filter=A --name-only --format= |
  sort -u | grep -E "$CRED_FILE_RE" | grep -Ev "$CRED_FILE_ALLOW_RE")
if [ -n "$files" ]; then
  problems+="[파일명] 크리덴셜로 보이는 파일이 커밋에 추가되어 있습니다."$'\n'
  problems+="$(printf '%s\n' "$files" | sed 's/^/  /')"$'\n'
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  problems+="[gitleaks] gitleaks가 설치되어 있지 않아 내용 검사를 하지 못했습니다. (brew install gitleaks)"$'\n'
else
  report=$(mktemp)
  trap 'rm -f "$report"' EXIT
  out=$(gitleaks git "$root" --log-opts="$LOG_OPTS" --redact --no-banner \
    --report-format json --report-path "$report" 2>&1)
  rc=$?
  count=$(jq 'length' "$report" 2>/dev/null) || count=0
  count=${count:-0}
  if [ "$count" -gt 0 ]; then
    problems+="[gitleaks] 비밀 값 ${count}건 (값은 가림 처리됨)"$'\n'
    problems+="$(jq -r '.[] | "  \(.File):\(.StartLine)  \(.RuleID)  commit \(.Commit[0:8])"' "$report" | clip 30)"$'\n'
  elif [ "$rc" -ne 0 ]; then
    problems+="[gitleaks] 검사 실패 (종료 코드 $rc)"$'\n'"$(printf '%s\n' "$out" | clip 20)"$'\n'
  fi
fi

[ -z "$problems" ] && exit 0

{
  echo "푸시할 커밋에서 크리덴셜 의심 항목이 발견되어 푸시를 막았습니다."
  echo
  printf '%s' "$problems"
  echo
  echo "사용자에게 알리고, 커밋 기록에서 제거할지 오탐으로 처리할지 확인받으세요."
  echo "오탐이면 .gitleaksignore 또는 줄 끝 gitleaks:allow 주석으로 제외할 수 있고, 사용자는 터미널에서 직접 푸시할 수도 있습니다."
} >&2
exit 2
