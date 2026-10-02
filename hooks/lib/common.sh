# hook 스크립트 공용 함수. 각 hook에서 source 해서 쓴다.

# stdin으로 받은 hook 입력 JSON에서 실행할 명령과 세션 cwd를 꺼낸다.
read_hook_input() {
  local input
  input=$(cat)
  HOOK_CMD=$(jq -r '.tool_input.command // empty' <<<"$input")
  HOOK_CWD=$(jq -r '.cwd // empty' <<<"$input")
}

# 명령 안에 `git <subcommand>` 호출이 있는지 본다.
# `git -C dir commit`, `cd dir && git push` 같은 형태도 잡는다.
has_git_subcommand() {
  local re="(^|[;&|({[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+$1([[:space:];&|)]|\$)"
  printf '%s\n' "$HOOK_CMD" | grep -Eq "$re"
}

# 명령이 실제로 실행될 저장소의 루트를 출력한다.
# 세션 cwd에서 시작해 명령 안의 `cd <dir>`, `git -C <dir>` 순으로 반영한다.
# 변수가 들어간 경로처럼 해석할 수 없으면 세션 cwd를 쓴다.
resolve_repo_root() {
  local dir="${HOOK_CWD:-$PWD}" arg
  arg=$(printf '%s\n' "$HOOK_CMD" | sed -nE 's/^(.*[;&|])?[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+).*/\2/p' | head -n 1)
  [ -n "$arg" ] && dir=$(_join_path "$dir" "$arg")
  arg=$(printf '%s\n' "$HOOK_CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^;&|[:space:]]+).*/\1/p' | head -n 1)
  [ -n "$arg" ] && dir=$(_join_path "$dir" "$arg")
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null ||
    git -C "${HOOK_CWD:-$PWD}" rev-parse --show-toplevel 2>/dev/null
}

_join_path() {
  local base=$1 p=$2
  p=${p#[\"\']}
  p=${p%[\"\']}
  case $p in
    *'$'* | *'`'*) printf '%s\n' "$base"; return ;;
  esac
  case $p in
    "~" | "~/"*) p="$HOME${p#\~}" ;;
    /*) ;;
    *) p="$base/$p" ;;
  esac
  printf '%s\n' "$p"
}

# 긴 출력은 앞의 N줄(기본 60)만 남긴다.
clip() {
  awk -v max="${1:-60}" 'NR <= max { print } END { if (NR > max) printf "  ... (%d줄 생략)\n", NR - max }'
}
