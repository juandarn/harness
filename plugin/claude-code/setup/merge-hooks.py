#!/usr/bin/env python3
# usage: merge-hooks.py <settings.json> <hooks-fragment.json> <plugin-root>
# Merges the plugin's hook entries into a settings.json, substituting $PLUGIN_ROOT with <plugin-root>.
import json
import os
import sys

settings_path, frag_path, plugin_root = sys.argv[1], sys.argv[2], sys.argv[3]
settings = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
frag = json.load(open(frag_path))
settings.setdefault("hooks", {})


def existing_commands(groups):
    return {h["command"] for g in groups for h in g.get("hooks", [])}


added = 0
for event, groups in frag.get("hooks", {}).items():
    bucket = settings["hooks"].setdefault(event, [])
    have = existing_commands(bucket)
    for group in groups:
        resolved = {k: v for k, v in group.items() if k != "hooks"}
        resolved["hooks"] = []
        for hook in group.get("hooks", []):
            command = hook["command"].replace("$PLUGIN_ROOT", plugin_root)
            if command in have:
                continue
            entry = dict(hook)
            entry["command"] = command
            resolved["hooks"].append(entry)
            added += 1
        if resolved["hooks"]:
            bucket.append(resolved)

json.dump(settings, open(settings_path, "w"), indent=2)
print(f"merged {added} hook(s) into {settings_path}")
