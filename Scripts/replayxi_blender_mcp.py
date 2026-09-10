#!/usr/bin/env python3
"""Use the installed local Blender MCP without restarting an active Codex task.

Run with the Python interpreter in uv's blender-mcp tool environment. The
normal Codex MCP connection uses the same server binary and privacy settings.
Only one client should operate on the live Blender scene at a time.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from importlib.metadata import version
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def invoke(args: argparse.Namespace) -> None:
    server = StdioServerParameters(
        command=str(args.server),
        env={
            **{key: os.environ[key] for key in ("PATH", "HOME", "USER", "TMPDIR", "LANG") if key in os.environ},
            "DISABLE_TELEMETRY": "true",
            "BLENDER_MCP_DISABLE_TELEMETRY": "1",
            "BLENDER_MCP_SAFE_MODE": "1",
            "BLENDER_HOST": "127.0.0.1",
            "BLENDER_PORT": "9876",
        },
    )
    async with stdio_client(server) as (read, write):
        async with ClientSession(read, write) as session:
            initialized = await session.initialize()
            results: dict[str, object] = {
                "server": initialized.serverInfo.model_dump(),
                "packageVersion": version("blender-mcp"),
                "host": "127.0.0.1:9876",
                "safeMode": True,
                "telemetryDisabled": True,
            }
            if args.script:
                result = await session.call_tool(
                    "execute_blender_code",
                    {"code": args.script.read_text(), "user_prompt": args.intent},
                )
                results["execution"] = compact_result(result)
            else:
                for name in ("get_addon_status", "get_scene_info"):
                    result = await session.call_tool(name, {"user_prompt": args.intent})
                    results[name] = compact_result(result)
            print(json.dumps(results, indent=2))
            for result in results.values():
                if isinstance(result, dict) and result.get("isError"):
                    raise RuntimeError("Blender MCP reported a tool error")


def compact_result(result) -> dict[str, object]:
    """Avoid printing the same MCP text in both content and structuredContent."""
    texts = [item.text for item in result.content if item.type == "text"]
    failed = bool(result.isError) or any(
        text.startswith(("Rejected by safe mode", "Error ", "Error:", "Could not"))
        for text in texts
    )
    values: list[object] = []
    for text in texts:
        try:
            values.append(json.loads(text))
        except json.JSONDecodeError:
            values.append(text)
    return {"isError": failed, "result": values[0] if len(values) == 1 else values}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, default=Path.home() / ".local/bin/blender-mcp")
    parser.add_argument("--script", type=Path, help="Reviewed Blender Python; MCP safety checks stay on")
    parser.add_argument("--intent", required=True, help="The user's instruction for this operation")
    args = parser.parse_args()
    # Launch exactly the file checked here, not a same-named PATH executable.
    args.server = args.server.expanduser().resolve()
    if not args.server.is_file():
        parser.error("Install Blender MCP before running this client")
    if args.script and (not args.script.is_file() or args.script.suffix != ".py"):
        parser.error("--script must identify a reviewed .py file")
    # A cold GLB import can exceed one minute. A timeout cancels the client,
    # not necessarily the operation Blender already received.
    timeout = 180 if args.script else 60
    try:
        asyncio.run(asyncio.wait_for(invoke(args), timeout=timeout))
    except TimeoutError:
        print(
            f"Blender MCP did not finish within {timeout}s. "
            "The operation may still be running in Blender. Inspect the scene "
            "before retrying; no automatic retry was attempted.",
            file=sys.stderr,
        )
        raise SystemExit(2) from None


if __name__ == "__main__":
    main()
