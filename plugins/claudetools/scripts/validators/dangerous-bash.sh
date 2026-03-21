#!/bin/bash
# Validator: block-dangerous-bash
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Calls: hook_get_field for command extraction
# Returns: 0 = safe, 2 = dangerous pattern detected (block)
# Output: block message written to stdout

validate_dangerous_bash() {
  local CMD
  CMD=$(hook_get_field '.tool_input.command')

  if [ -z "$CMD" ]; then
    return 0
  fi

  local BLOCKED=""

  # --- Destructive filesystem operations ---
  # rm -rf with broad paths (/, ~, $HOME, ../) or --no-preserve-root
  if echo "$CMD" | grep -qE 'rm\s+-rf\s+(/|~|\$HOME|\.\./)|--no-preserve-root'; then
    BLOCKED="Blocked: rm -rf on broad path"
  fi

  # chmod 777 (world-writable permissions), including with -R flag
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'chmod\s+(-[a-zA-Z]+\s+)*777'; then
    BLOCKED="Blocked: chmod 777 (world-writable permissions)"
  fi

  # --- Destructive git operations ---
  # git reset --hard
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+reset\s+--hard'; then
    BLOCKED="Blocked: git reset --hard (destructive, may lose work)"
  fi

  # git push --force/-f to main/master
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+push\s+.*(--force|-f).*(main|master)'; then
    BLOCKED="Blocked: force push to main/master"
  fi

  # git clean -f (deletes untracked files)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
    BLOCKED="Blocked: git clean -f (deletes untracked files)"
  fi

  # git add -A / git add . (force explicit file staging)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+add\s+(-A|--all|\.\s*$|\.\s+)'; then
    BLOCKED="Blocked: git add -A/. (stage specific files to avoid accidental secret commits)"
  fi

  # git add of secrets (.env*, *.pem, *.key, *credentials*)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+add\s+.*(\.(env|pem|key)|credentials)'; then
    BLOCKED="Blocked: git add of sensitive file (.env/.pem/.key/credentials)"
  fi

  # --- Supply chain / network risks ---
  # curl/wget piped to sh/bash
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(curl|wget).*\|\s*(ba)?sh'; then
    BLOCKED="Blocked: curl/wget piped to shell (supply chain risk)"
  fi

  # npm publish / pip upload (accidental package publishing)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(npm\s+publish|pip\s+upload|twine\s+upload|yarn\s+publish)'; then
    BLOCKED="Blocked: package publish/upload (accidental publishing risk)"
  fi

  # --- Secret leakage ---
  # cat/echo/print of .env files piped to other commands
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(cat|echo|printf|print)\s+.*\.env.*\|'; then
    BLOCKED="Blocked: .env content piped to another command (secret leakage risk)"
  fi

  # --- Container security ---
  # docker run --privileged (container escape risk)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'docker\s+run\s+.*--privileged'; then
    BLOCKED="Blocked: docker run --privileged (container escape risk)"
  fi

  # --- Bulk file deletion via find ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'find\s.*(-delete|--delete)'; then
    BLOCKED="Blocked: find -delete (bulk file deletion)"
  fi

  # dd writing to device
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '\bdd\s+.*of=/dev/'; then
    BLOCKED="Blocked: dd writing to device"
  fi

  # --- Disk/filesystem destruction ---
  # mkfs, fdisk, wipefs, parted on devices
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '\b(mkfs|fdisk|wipefs|parted)\b.*(/dev/|/disk)'; then
    BLOCKED="Blocked: disk/filesystem destruction command"
  fi

  # --- Reverse shells ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '/dev/tcp/|nc\s+.*-e\s|ncat\s+.*-e\s'; then
    BLOCKED="Blocked: reverse shell pattern detected"
  fi
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE "python[23]?\s+-c\s+.*socket.*subprocess|perl\s+-e\s+.*socket.*exec"; then
    BLOCKED="Blocked: reverse shell pattern detected"
  fi

  # --- Environment destruction ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'export\s+PATH\s*=\s*""'; then
    BLOCKED="Blocked: clearing PATH (environment destruction)"
  fi

  # --- Deploy without typecheck gate ---
  # Block deploy commands unless typecheck was run recently (same chain OR recent session history)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(npm\s+run\s+deploy|wrangler\s+deploy|vercel\s+deploy|netlify\s+deploy)'; then
    local TYPECHECK_OK=0
    # Check 1: typecheck in the same command chain (&&)
    echo "$CMD" | grep -qE '(tsc|typecheck|type-check).*&&.*(deploy)' && TYPECHECK_OK=1
    # Check 2: recent typecheck in session hook logs (last 30 entries, ~last few minutes)
    if [ "$TYPECHECK_OK" -eq 0 ]; then
      local LOG_FILE="${CLAUDE_PLUGIN_ROOT:-}/logs/hooks.log"
      if [ -f "$LOG_FILE" ]; then
        local RECENT_TC
        RECENT_TC=$(tail -30 "$LOG_FILE" 2>/dev/null | grep -ciE 'tsc|typecheck|type-check|npx tsc' || echo 0)
        [ "$RECENT_TC" -gt 0 ] && TYPECHECK_OK=1
      fi
    fi
    if [ "$TYPECHECK_OK" -eq 0 ]; then
      BLOCKED="Blocked: deploy without typecheck. Run typecheck first, then deploy."
    fi
  fi

  # --- Database destruction ---
  # DROP DATABASE / DROP TABLE without WHERE (SQL injection or accident)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qiE '(DROP\s+(DATABASE|TABLE|SCHEMA)\b|TRUNCATE\s+TABLE)'; then
    BLOCKED="Blocked: SQL DROP/TRUNCATE command (destructive database operation)"
  fi

  # --- Infrastructure destruction ---
  # terraform destroy, kubectl delete namespace, aws ec2 terminate
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(terraform\s+destroy|kubectl\s+delete\s+namespace|aws\s+.*terminate-instances|gcloud\s+.*delete\s+.*--quiet)'; then
    BLOCKED="Blocked: infrastructure destruction command — requires explicit user confirmation"
  fi

  # --- Credential exposure ---
  # Printing secrets to stdout or piping them
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(echo|cat|printf)\s+.*(\$[A-Z_]*(SECRET|TOKEN|KEY|PASSWORD|CREDENTIALS|API_KEY))'; then
    BLOCKED="Blocked: credential exposure via stdout (potential secret leakage)"
  fi

  # --- System service disruption ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(systemctl\s+(stop|disable|mask)\s|service\s+\w+\s+stop|kill\s+-9\s+1\b|killall)'; then
    BLOCKED="Blocked: system service disruption command"
  fi

  # --- Uncommitted work destruction ---
  # git checkout . / git restore . (discards all uncommitted changes)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+(checkout|restore)\s+\.\s*$'; then
    BLOCKED="Blocked: git ${BASH_REMATCH[1]:-checkout/restore} . discards ALL uncommitted changes. Uncommitted work may belong to other agents or manual edits. Stage and commit changes first, or target specific files instead."
  fi

  # --- Fork bombs ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE ':\(\)\s*\{.*\|.*&\s*\}\s*;|\./(.*)\s*\|\s*\./\1\s*&'; then
    BLOCKED="Blocked: fork bomb pattern detected (will crash the system)"
  fi

  # --- Crontab persistence ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'crontab\s+(-r|-e)|echo\s+.*>>\s*/etc/cron|echo\s+.*\|\s*crontab'; then
    BLOCKED="Blocked: crontab modification (persistence mechanism). Verify this is intentional."
  fi

  # --- SSH key manipulation ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'echo\s+.*>>\s*.*authorized_keys|cp\s+.*authorized_keys|cat\s+.*id_rsa\b'; then
    BLOCKED="Blocked: SSH key manipulation detected (potential unauthorized access)"
  fi

  # --- History/log wiping ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'history\s+-c|>\s*~/\.bash_history|>\s*~/\.(zsh_history|histfile)|unset\s+HISTFILE|shred\s+.*history'; then
    BLOCKED="Blocked: shell history wiping (anti-forensics pattern)"
  fi

  # --- Hallucinated package detection ---
  # Flag packages with 5+ hyphenated segments (likely hallucinated)
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(npm|pnpm|yarn)\s+(install|add)\s+(@[a-z0-9-]+/)?[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+'; then
    BLOCKED="Warning: Package name looks hallucinated (too many hyphenated segments) — verify it exists"
  fi
  # Flag pip install of suspiciously long package names
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'pip3?\s+install\s+[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+'; then
    BLOCKED="Warning: pip package name looks hallucinated — verify it exists on PyPI"
  fi

  # --- AI tool safety bypass flags (Nx/Clinejection attack pattern, Feb 2026) ---
  # Attackers use npm lifecycle scripts to invoke AI tools with permission-bypass flags
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE -- '--dangerously-skip-permissions|--yolo|--trust-all-tools|--no-safety|--disable-guardrails'; then
    BLOCKED="Blocked: AI tool safety bypass flag detected. This pattern was used in the Nx supply chain attack (Feb 2026) to turn AI assistants into exfiltration tools. Never run AI tools with permission-bypass flags."
  fi

  # --- MCP server injection ---
  # Malware injects rogue MCP servers into AI tool configs
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(echo|cat|printf|tee).*mcp.*server.*>>?\s*(settings|config|\.claude|\.cursor|\.continue)'; then
    BLOCKED="Blocked: Potential MCP server injection into AI tool config. Verify the MCP server source before adding it."
  fi

  # --- npm lifecycle script abuse ---
  # Malicious postinstall/preinstall scripts that invoke AI tools or exfiltrate data
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'npm\s+set\s+.*script.*=.*claude|npm\s+pkg\s+set\s+.*postinstall|npm\s+pkg\s+set\s+.*preinstall'; then
    BLOCKED="Blocked: npm lifecycle script modification — malicious lifecycle scripts are a primary supply chain attack vector."
  fi

  # --- Token/credential exfiltration via curl/wget ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(curl|wget)\s+.*(-d|--data|--data-raw)\s+.*(\$[A-Z_]*(TOKEN|SECRET|KEY|PASSWORD)|gh\s+auth\s+token)'; then
    BLOCKED="Blocked: credential exfiltration attempt — sending tokens/secrets to an external endpoint."
  fi

  # --- Git credential theft ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+credential\s+fill|git\s+credential.*get|gh\s+auth\s+token.*\|'; then
    BLOCKED="Blocked: git credential extraction — this can expose authentication tokens."
  fi

  # --- Encoded command execution (circumvention of pattern matching) ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'base64\s+(-d|--decode)\s*\|\s*(ba)?sh'; then
    BLOCKED="Blocked: base64-encoded command piped to shell — this bypasses command pattern detection."
  fi

  # --- eval with dynamic content (circumvention risk) ---
  if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '\beval\s+"?\$(\(|[A-Z_])'; then
    BLOCKED="Blocked: eval with dynamic content — construct commands explicitly instead of using eval."
  fi

  if [ -n "$BLOCKED" ]; then
    record_hook_outcome "block-dangerous-bash" "PreToolUse" "block" "Bash" "" "" "$MODEL_FAMILY"
    echo "$BLOCKED"
    return 2
  fi

  record_hook_outcome "block-dangerous-bash" "PreToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
  return 0
}
