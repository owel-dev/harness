#!/usr/bin/env bash
# PreToolUse(Bash) hook: git commit 전에 의존성 보안 취약점을 검사한다.
#
# 저장소 루트의 lockfile을 보고 검사 도구를 고른다.
#   pnpm-lock.yaml                         pnpm audit (high 이상이면 문제)
#   package-lock.json, npm-shrinkwrap.json npm audit (high 이상이면 문제)
#   그 밖의 lockfile                        osv-scanner (심각도 무관)
#
# 문제가 나오면(검사 도구가 없거나 검사가 실패한 경우 포함)
#   이번 커밋에 의존성 파일 변경이 있으면 커밋을 막는다 (exit 2).
#   변경이 없으면 기존 취약점이므로 막지 않고 경고만 남긴다.

set -o pipefail
. "$(dirname "$0")/lib/common.sh"

read_hook_input
has_git_subcommand commit || exit 0
root=$(resolve_repo_root) || exit 0

DEP_FILE_RE='(^|/)(package(-lock)?\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|requirements[^/]*\.txt|pyproject\.toml|poetry\.lock|uv\.lock|Pipfile(\.lock)?|Cargo\.(toml|lock)|go\.(mod|sum)|Gemfile(\.lock)?|composer\.(json|lock)|pom\.xml|build\.gradle(\.kts)?|gradle\.lockfile)$'
OSV_LOCKFILES='yarn.lock requirements.txt poetry.lock uv.lock Pipfile.lock Cargo.lock go.mod Gemfile.lock composer.lock pom.xml gradle.lockfile'

report=""

# $1: 이름, $2: 통과로 볼 종료 코드(공백 구분), 나머지: 실행할 명령
check() {
  local name=$1 ok=$2 out rc
  shift 2
  if ! command -v "$1" >/dev/null 2>&1; then
    report+="[$name] $1 이(가) 설치되어 있지 않아 검사하지 못했습니다. (brew install $1)"$'\n'
    return
  fi
  out=$(cd "$root" && "$@" 2>&1)
  rc=$?
  case " $ok " in *" $rc "*) return ;; esac
  report+="[$name] 종료 코드 $rc"$'\n'"$(printf '%s\n' "$out" | clip 60)"$'\n'
}

if [ -f "$root/pnpm-lock.yaml" ]; then
  check "pnpm audit" "0" pnpm audit --audit-level high
elif [ -f "$root/package-lock.json" ] || [ -f "$root/npm-shrinkwrap.json" ]; then
  check "npm audit" "0" npm audit --audit-level=high
fi

osv_args=()
for f in $OSV_LOCKFILES; do
  [ -f "$root/$f" ] && osv_args+=(-L "$root/$f")
done
if [ ${#osv_args[@]} -gt 0 ]; then
  # 0: 취약점 없음, 128: 검사할 패키지 없음
  check "osv-scanner" "0 128" osv-scanner scan source "${osv_args[@]}"
fi

[ -z "$report" ] && exit 0

# 커밋에 들어갈 수 있는 변경(staged, unstaged, untracked) 중 의존성 파일
changed=$({
  git -C "$root" diff --name-only HEAD 2>/dev/null || git -C "$root" diff --name-only --cached
  git -C "$root" ls-files --others --exclude-standard
} | grep -E "$DEP_FILE_RE" | sort -u)

if [ -n "$changed" ]; then
  {
    echo "의존성 취약점 검사에서 문제가 나와 커밋을 막았습니다."
    echo "이번 커밋에 포함될 수 있는 의존성 파일 변경:"
    printf '%s\n' "$changed" | sed 's/^/  /'
    echo
    printf '%s' "$report"
    echo
    echo "사용자에게 결과를 알리고 진행 방법을 확인받으세요. 사용자는 터미널에서 직접 커밋할 수도 있습니다."
  } >&2
  exit 2
fi

msg="의존성 취약점 검사에서 문제가 나왔지만, 이번 커밋에는 의존성 파일 변경이 없어 커밋은 진행합니다."
jq -n --arg sys "$msg" --arg ctx "$msg"$'\n'"$report" '{
  systemMessage: $sys,
  hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $ctx }
}'
exit 0
