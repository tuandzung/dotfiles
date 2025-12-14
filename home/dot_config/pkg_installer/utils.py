from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

import yaml

from logger import logger

def run_hook(hook_commands: str | None) -> None:
    """Run a hook by executing the specified commands."""
    if not hook_commands:
        return None

    logger.info("Running hook...")
    subprocess.run(hook_commands, shell=True, check=True)

def handle_version_tags(s: str, version: str) -> str:
    ret_s = s
    if s.find("%1s") != -1:
        ret_s = s.replace("%1s", "v%s") % version
    elif s.find("%s") != -1:
        ret_s = s % version
    return ret_s

def load_all_tools() -> list[dict[str, Any]]:
    with open(f"{Path.home()}/.config/pkg_installer/tools.yaml") as f:
        tools = list(yaml.safe_load(f) or [])

    return tools

def get_os_info() -> dict[str, str]:
    with open(f"{Path.home()}/.config/pkg_installer/os_info.yaml") as f:
        return yaml.safe_load(f) or {}

