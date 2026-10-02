# hooks

Claude Code `PreToolUse` hook 스크립트. Claude가 Bash 도구로 실행하는 명령에만 적용되고, 사용자가 터미널에서 직접 실행하는 git 명령에는 걸리지 않는다.

| 스크립트 | 시점 | 동작 |
|---|---|---|
| `pre-commit-audit.sh` | `git commit` 전 | lockfile 기준으로 의존성 취약점을 검사한다. 문제가 있을 때 이번 커밋에 의존성 파일 변경이 있으면 막고, 없으면 경고만 남긴다. |
| `pre-push-secrets.sh` | `git push` 전 | 아직 원격에 없는 커밋을 대상으로 크리덴셜 파일명과 gitleaks 내용 검사를 한다. 걸리면 막는다. |

## 등록

`~/.claude/settings.json`에 추가한다.

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        { "type": "command", "command": "/Users/user/harness/hooks/pre-commit-audit.sh", "timeout": 180 },
        { "type": "command", "command": "/Users/user/harness/hooks/pre-push-secrets.sh", "timeout": 120 }
      ]
    }
  ]
}
```

## 필요한 도구

- `jq`, `gitleaks`
- JS 프로젝트: `npm` 또는 `pnpm`
- 그 밖의 언어(yarn, Python, Rust, Go 등): `osv-scanner`

## 알려진 한계

- hook은 명령 실행 전에 돌기 때문에, 같은 명령 안에서 파일을 고치고 바로 커밋하면 그 변경은 보지 못한다.
- `cd "$DIR"`처럼 경로에 변수가 들어가면 해석하지 않고 세션 cwd 기준으로 검사한다.
- timeout을 넘기면 검사 없이 명령이 진행된다.
