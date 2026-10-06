#!/usr/bin/env python3
"""Summarize persisted Micro inputs without exposing session identities.

Requires Python 3.11+. Reads files only; does not contact Codex or the device.
This is an inventory of partial inputs, not a live six-slot model provider.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import tomllib


GLOBAL_KEYS = (
    "pinned-thread-ids",
    "pinned-project-ids",
    "app-server-migrated-pinned-thread-ids-by-host",
    "sidebar-project-thread-orders",
)
ATOM_KEYS = (
    "unified-sidebar-pinned-order-v1",
    "app-server-pinned-thread-order-v1",
    "flat-project-sidebar-preferences-v1",
    "codex-micro-custom-agent-assignments",
)


def describe(container, key):
    if key not in container:
        return {"present": False}
    value = container[key]
    # Never return keys or contents of these collections: they identify chats.
    result = {"present": True, "type": type(value).__name__}
    if isinstance(value, (list, dict)):
        result["entryCount"] = len(value)
    return result


def inspect(codex_directory, app_directory):
    with (codex_directory / "config.toml").open("rb") as stream:
        config = tomllib.load(stream)
    state = json.loads((codex_directory / ".codex-global-state.json").read_text())
    atoms = state.get("electron-persisted-atom-state", {})
    desktop = config.get("desktop", {})
    if not all(isinstance(value, dict) for value in (state, atoms, desktop)):
        raise ValueError("Unexpected persisted-state schema")
    with (app_directory / "Contents/Info.plist").open("rb") as stream:
        app = plistlib.load(stream)

    configured_source = desktop.get("codex-micro-agent-source")
    # Whitelist known scalar values instead of echoing arbitrary config data.
    source = configured_source if configured_source in ("pinned", "recent", "priority", "custom") else None
    return {
        "schemaVersion": 1,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "readOnly": True,
        "deviceOpened": False,
        "sessionIdentitiesIncluded": False,
        "app": {
            "bundleId": app.get("CFBundleIdentifier"),
            "version": app.get("CFBundleShortVersionString"),
            "build": app.get("CFBundleVersion"),
        },
        "configuredAgentSource": source,
        "configuredAgentSourceRecognized": source is not None,
        "persistedInputs": {
            "globalState": {key: describe(state, key) for key in GLOBAL_KEYS},
            "persistedAtoms": {key: describe(atoms, key) for key in ATOM_KEYS},
        },
        "liveModel": {
            "providerImplemented": False,
            "safeToDriveHardware": False,
            "missingVerifiedInputs": [
                "Resolved ordered six slots matching the native renderer",
                "Current per-slot status and status-priority inputs",
                "Current selection, window focus and pulsing flags",
                "Current brightness and complete keys/ambient zone model",
                "Ordered updates and freshness across host, layer and device changes",
            ],
        },
        "scope": "Counts of persisted candidate inputs only. Presence does not establish freshness or native six-slot identity. No conversation transcript files, live app memory or HID traffic were read; session titles and identities are excluded from output.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex-directory", type=Path, default=Path.home() / ".codex")
    parser.add_argument("--app", type=Path, default=Path("/Applications/ChatGPT.app"))
    args = parser.parse_args()
    try:
        report = inspect(args.codex_directory, args.app)
    except (OSError, ValueError, TypeError, AttributeError) as error:
        # Parser exceptions can contain source text; don't echo the exception.
        print(json.dumps({"readOnly": True, "status": "unavailable", "errorType": type(error).__name__}))
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
