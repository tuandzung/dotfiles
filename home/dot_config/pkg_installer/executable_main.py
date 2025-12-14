from __future__ import annotations

import sys

from binary_installer import binaries_installer, cleanup
from os_installer import os_packages_installer
from shell_installer import shell_installer

from logger import logger
from utils import get_os_info, load_all_tools

def main(argv: list[str]) -> int:
    tools = load_all_tools()

    tools_os = [tool for tool in tools if tool and tool.get("method") == "os"]
    tools_bin = [tool for tool in tools if tool and tool.get("method") == "binary"]
    tools_shell = [tool for tool in tools if tool and tool.get("method") == "shell"]

    os_info = get_os_info()

    os_info = get_os_info()
    logger.info(f"Detected OS: {os_info.get('name')}")
    detected_os = os_info.get("shortCode")

    os_packages_installer(detected_os, tools_os)
    binaries_installer(tools_bin)
    shell_installer(tools_shell)

    cleanup()
    logger.info("All tools downloaded and installed.")
    return 0

def cli() -> None:
    raise SystemExit(main(sys.argv))

if __name__ == "__main__":
    cli()
