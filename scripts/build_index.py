#!/usr/bin/env python3
"""scripts/build_index.py -- regenerate index.json from plugins/*.lua.

Compiles every plugin in plugins/ in a fresh Lua runtime, reads its manifest,
counts its commands and tools, and writes the marketplace catalogue that
Archimedes reads to search and install plugins.

The script needs only the `lupa` package. Run it after adding or editing a
plugin; CI fails if index.json is stale.
"""
from __future__ import annotations

import json
import os
import sys

_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PLUGIN_DIR = os.path.join(_REPO, "plugins")
_INDEX_PATH = os.path.join(_REPO, "index.json")


def _lua_to_py(value):
    """Convert a Lua table / scalar into Python."""
    from lupa import lua_type

    if lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if not keys:
        return {}
    if (all(isinstance(k, int) for k in keys)
            and sorted(keys) == list(range(1, len(keys) + 1))):
        return [_lua_to_py(value[k]) for k in range(1, len(keys) + 1)]
    return {str(k): _lua_to_py(value[k]) for k in keys}


def _read_plugin(path: str):
    """Return (manifest, commands, tools) for one plugin file."""
    from lupa import LuaRuntime

    runtime = LuaRuntime(
        unpack_returned_tuples=True,
        register_eval=False,
        register_builtins=False,
    )
    with open(path, "r", encoding="utf-8") as fh:
        table = runtime.execute(fh.read())
    manifest = _lua_to_py(table["manifest"]) or {}
    commands = _lua_to_py(table["commands"]) or []
    tools = _lua_to_py(table["tools"]) or []
    return manifest, commands, tools


def _names(items: list) -> list[str]:
    return [str(it["name"]) for it in items
            if isinstance(it, dict) and it.get("name")]


def build() -> int:
    entries: list[dict] = []
    for fname in sorted(os.listdir(_PLUGIN_DIR)):
        if not fname.endswith(".lua"):
            continue
        plugin_id = fname[:-4]
        manifest, commands, tools = _read_plugin(
            os.path.join(_PLUGIN_DIR, fname))
        if manifest.get("id") != plugin_id:
            print(f"ERROR: {fname}: manifest id {manifest.get('id')!r} "
                  f"does not match the file name", file=sys.stderr)
            return 1
        entries.append({
            "id": plugin_id,
            "name": manifest.get("name", plugin_id),
            "version": manifest.get("version", "0.0.0"),
            "description": manifest.get("description", ""),
            "author": manifest.get("author", ""),
            "category": manifest.get("category", "General"),
            "path": f"plugins/{fname}",
            "commands": _names(commands),
            "tools": _names(tools),
        })
    with open(_INDEX_PATH, "w", encoding="utf-8") as fh:
        json.dump({"plugins": entries}, fh, indent=2)
        fh.write("\n")
    print(f"Wrote index.json with {len(entries)} plugin(s): "
          + ", ".join(e["id"] for e in entries))
    return 0


if __name__ == "__main__":
    sys.exit(build())
