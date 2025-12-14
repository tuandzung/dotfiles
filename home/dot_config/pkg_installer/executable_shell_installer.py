from __future__ import annotations

import argparse
import os
import subprocess
import sys
from collections.abc import Iterable, Iterator
from pathlib import Path
from typing import NotRequired, TypedDict

from logger import logger
from utils import load_all_tools

class ShellTool(TypedDict, total=False):
    """Shell tool definition."""

    name: str
    method: str
    is_essential: bool
    dependencies: list[str]
    content: str
    # allow other keys (e.g. metadata) without typing every field
    description: NotRequired[str]

def run_shell_command(command: str) -> None:
    logger.info(f"Running command: {command}")
    try:
        subprocess.run(command, shell=True, check=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"Failed to run command: {exc}") from exc

def _iter_shell_tools(all_tools: Iterable[ShellTool]) -> Iterator[ShellTool]:
    for tool in all_tools:
        if tool and tool.get("method") == "shell":
            yield tool

def _find_dependencies(dependency_names: Iterable[str]) -> list[ShellTool]:
    wanted = set(dependency_names)
    all_tools = load_all_tools()
    return [tool for tool in all_tools if tool and tool.get("name") in wanted]

def install_dependencies(dependencies: Iterable[str]) -> None:
    deps = _find_dependencies(dependencies)
    for dep in deps:
        dep_method = dep.get("method")
        dep_name = dep.get("name")
        if not dep_method or not dep_name:
            continue
        logger.info(f"Installing dependency: {dep_name}")
        run_shell_command(f"tep_{dep_method} -t {dep_name}")

def shell_installer(packages: Iterable[ShellTool]) -> None:
    flag_install_is_essential_only = os.environ.get("FLAG_INSTALL_IS_ESSENTIAL_ONLY")

    for pkg in packages:
        name = pkg.get("name", "")
        is_essential = pkg.get("is_essential", False)
        dependencies = pkg.get("dependencies", [])
        content = pkg.get("content")

        if flag_install_is_essential_only and not is_essential:
            logger.info(f"{name} is not an essential tool, skipping...")
            continue

        logger.info(f"Installing package: {name}")

        if dependencies:
            logger.info(f"Installing dependencies for {name}...")
            install_dependencies(dependencies)

        if content:
            run_shell_command(content)

        logger.info(f"Package {name} installed successfully.")

def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog=Path(argv[0]).name)
    parser.add_argument(
        "-e",
        "--essential-only",
        action="store_true",
        help="Install only tools marked as essential",
    )
    parser.add_argument(
        "-t",
        "--tool",
        dest="tool",
        default=None,
        help="Install only one specific tool",
    )
    parser.add_argument("tool_positional", nargs="?", default=None)
    return parser.parse_args(argv[1:])

def main(argv: list[str]) -> int:
    try:
        args = _parse_args(argv)
        if args.essential_only:
            os.environ["FLAG_INSTALL_IS_ESSENTIAL_ONLY"] = "true"

        all_tools = load_all_tools()
        tools = list(_iter_shell_tools(all_tools))

        tool_name = args.tool or args.tool_positional
        if tool_name:
            tools = [tool for tool in tools if tool.get("name") == tool_name]

        if not tools:
            logger.warning(f'No tool with method: "shell" found with name: "{tool_name or ""}"')
            return 0

        shell_installer(tools)
        return 0
    except Exception as exc:
        logger.error(str(exc))
        return 1

def cli() -> None:
    raise SystemExit(main(sys.argv))

if __name__ == "__main__":
    cli()
