#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/traffic_light_hook.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

chmod +x "$HOOK_SCRIPT"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{"hooks":{}}' > "$SETTINGS_FILE"
fi

python3 - "$SETTINGS_FILE" "$HOOK_SCRIPT" << 'PYEOF'
import json, sys

settings_path, hook_script = sys.argv[1], sys.argv[2]

with open(settings_path, 'r') as f:
    settings = json.load(f)

if 'hooks' not in settings:
    settings['hooks'] = {}

# Define traffic light hooks
tl_hooks = {
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": f"{hook_script} idle"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": f"{hook_script} idle"}]}],
    "PreToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": f"{hook_script} working"}]}],
    "PostToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": f"{hook_script} working"}]}],
    "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": f"{hook_script} input"}]}],
}

# Merge: add traffic light hooks, preserving existing ones
for event, hooks in tl_hooks.items():
    existing = settings['hooks'].get(event, [])
    # Remove old traffic light hooks (by script path pattern)
    filtered = [h for h in existing if not any(
        'traffic_light_hook' in hh.get('command', '') for hh in h.get('hooks', [])
    )]
    # Add new ones at the beginning
    settings['hooks'][event] = hooks + filtered

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print(f"Hooks installed to {settings_path}")
PYEOF

echo ""
echo "Done! Now:"
echo "  1. echo 'idle' > /tmp/claude_traffic_light_state"
echo "  2. Launch ClaudeTrafficLight.app"
echo "  3. Start Claude Code — the traffic light will track its state"
