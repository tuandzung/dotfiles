from __future__ import annotations

import argparse
import os
import platform
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import NotRequired, TypedDict

from logger import logger
from utils import get_os_info, load_all_tools, run_hook

class HookConfig(TypedDict, total=False):
    """Configuration for hooks to run before or after package installation."""

    before: str
    after: str

class PackageConfig(TypedDict, total=False):
    """Configuration for a package to be installed."""

    name: str
    repo: NotRequired[str]
    accept_keywords: NotRequired[str]
    use: NotRequired[str]
    cask: NotRequired[bool]
    repo_version: NotRequired[str]
    key: NotRequired[str]

class OsConfig(TypedDict, total=False):
    """Configuration for the operating system."""

    packages: list[PackageConfig]
    hook: HookConfig

class ToolConfig(TypedDict, total=False):
    """Configuration for a tool to be installed."""

    name: str
    method: str
    is_essential: bool
    gentoo: NotRequired[OsConfig]
    arch: NotRequired[OsConfig]
    ubuntu: NotRequired[OsConfig]
    macos: NotRequired[OsConfig]
    termux: NotRequired[OsConfig]

def detect_os() -> str:
    """Detect the current operating system."""
    system = platform.system().lower()
    if system == "linux":
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("ID="):
                    return line.strip().split("=")[1].strip('"')
    if system == "darwin":
        return "macos"
    if system == "android":
        return "termux"
    return system

def update_repositories(os_type: str) -> None:
    """Update repositories for the detected OS."""
    logger.info("Updating repositories...")
    if os_type == "gentoo":
        subprocess.run(["sudo", "emerge", "--sync"], check=True)
    elif os_type == "arch":
        subprocess.run(["yay", "-Sy"], check=True)
    elif os_type == "ubuntu":
        subprocess.run(["sudo", "apt", "update"], check=True)
    elif os_type == "macos":
        subprocess.run(["brew", "update"], check=True)
    elif os_type == "termux":
        subprocess.run(["pkg", "update"], check=True)
    else:
        raise ValueError(f"Unsupported OS: {os_type}")
    logger.info("Repository update completed successfully.")

def is_package_installed_gentoo(package_name: str) -> bool:
    """Check if a package is installed on Gentoo."""
    result = subprocess.run(
        ["qlist", "-I", package_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode == 0

def is_package_installed_arch(package_name: str) -> bool:
    """Check if a package is installed on Arch Linux."""
    result = subprocess.run(
        ["pacman", "-Qi", package_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode == 0

def is_package_installed_macos(package_name: str, cask: bool = False) -> bool:
    """Check if a package is installed on macOS."""
    cmd = ["brew", "list", "--cask", package_name] if cask else ["brew", "list", package_name]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    return result.returncode == 0

def is_package_installed_ubuntu(package_name: str) -> bool:
    """Check if a package is installed on Ubuntu."""
    result = subprocess.run(
        ["dpkg", "-s", package_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode == 0

def is_package_installed_termux(package_name: str) -> bool:
    """Check if a package is installed on Termux."""
    result = subprocess.run(
        ["pkg", "list-installed", package_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode == 0

def _run_os_hooks(hooks: HookConfig | None, when: str) -> None:
    if hooks and when in hooks:
        run_hook(hooks[when])

def install_packages_gentoo(packages: Iterable[PackageConfig], hooks: HookConfig | None) -> None:
    """Install packages on Gentoo using emerge, handle package.use, and add overlays."""
    packages_to_install: list[PackageConfig] = []
    for pkg in packages:
        name = pkg.get("name")
        if not name:
            continue
        if is_package_installed_gentoo(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue
        packages_to_install.append(pkg)

    if not packages_to_install:
        logger.info("All packages are already installed; skipping hooks.")
        return

    _run_os_hooks(hooks, "before")

    for pkg in packages_to_install:
        name = pkg.get("name")
        if not name:
            continue
        repo = pkg.get("repo")
        accept_keywords = pkg.get("accept_keywords", "")
        use_flags = pkg.get("use", "")
        base_name = name.split("/", 1)[1] if "/" in name else name

        if repo:
            logger.info(f"Adding and enabling overlay: {repo}...")
            subprocess.run(["sudo", "eselect", "repository", "enable", repo], check=True)
            subprocess.run(["sudo", "emerge", "--sync", repo], check=True)
            name = f"{name}::{repo}"

        if accept_keywords:
            accept_keywords_path = f"/etc/portage/package.accept_keywords/{base_name}"
            subprocess.run(["sudo", "mkdir", "-p", os.path.dirname(accept_keywords_path)], check=True)
            subprocess.run(["sudo", "touch", accept_keywords_path], check=True)
            echo_cmd = subprocess.run(["echo", accept_keywords], check=True, capture_output=True)
            subprocess.run(["sudo", "tee", accept_keywords_path], input=echo_cmd.stdout, check=True)

        if use_flags:
            use_flags_path = f"/etc/portage/package.use/{base_name}"
            subprocess.run(["sudo", "mkdir", "-p", os.path.dirname(use_flags_path)], check=True)
            subprocess.run(["sudo", "touch", use_flags_path], check=True)
            echo_cmd = subprocess.run(["echo", use_flags], check=True, capture_output=True)
            subprocess.run(["sudo", "tee", use_flags_path], input=echo_cmd.stdout, check=True)

        logger.info(f"Installing {name}...")
        subprocess.run(
            ["sudo", "emerge", "--ask", "n", "--quiet-build", "--noreplace", name],
            check=True,
        )

    _run_os_hooks(hooks, "after")

def install_packages_arch(packages: Iterable[PackageConfig], hooks: HookConfig | None) -> None:
    """Install packages on Arch Linux using yay/pacman."""
    packages_to_install: list[PackageConfig] = []
    for pkg in packages:
        name = pkg.get("name")
        if not name:
            continue
        if is_package_installed_arch(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue
        packages_to_install.append(pkg)

    if not packages_to_install:
        logger.info("All packages are already installed; skipping hooks.")
        return

    _run_os_hooks(hooks, "before")

    for pkg in packages_to_install:
        name = pkg.get("name")
        if not name:
            continue

        logger.info(f"Installing {name}...")
        subprocess.run(
            [
                "yay",
                "-S",
                "--noconfirm",
                "--needed",
                "--answerclean",
                "All",
                "--answerdiff",
                "None",
                name,
            ],
            check=True,
        )

    _run_os_hooks(hooks, "after")

def install_packages_macos(packages: Iterable[PackageConfig], hooks: HookConfig | None) -> None:
    """Install packages on macOS using Homebrew and Homebrew Cask."""
    packages_to_install: list[PackageConfig] = []
    for pkg in packages:
        name = pkg.get("name")
        if not name:
            continue
        cask = bool(pkg.get("cask", False))
        if is_package_installed_macos(name, cask):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue
        packages_to_install.append(pkg)

    if not packages_to_install:
        logger.info("All packages are already installed; skipping hooks.")
        return

    _run_os_hooks(hooks, "before")

    for pkg in packages_to_install:
        name = pkg.get("name")
        if not name:
            continue
        cask = bool(pkg.get("cask", False))

        if cask:
            logger.info(f"Installing Cask package: {name}...")
            subprocess.run(["brew", "install", "--cask", name], check=True)
        else:
            logger.info(f"Installing Homebrew package: {name}...")
            subprocess.run(["brew", "install", name], check=True)

    _run_os_hooks(hooks, "after")

def install_packages_ubuntu(packages: Iterable[PackageConfig], hooks: HookConfig | None) -> None:
    """Install packages on Ubuntu using apt."""
    packages_to_install: list[PackageConfig] = []
    for pkg in packages:
        name = pkg.get("name")
        if not name:
            continue
        if is_package_installed_ubuntu(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue
        packages_to_install.append(pkg)

    if not packages_to_install:
        logger.info("All packages are already installed; skipping hooks.")
        return

    _run_os_hooks(hooks, "before")

    for pkg in packages_to_install:
        name = pkg.get("name")
        if not name:
            continue
        repo = pkg.get("repo")
        repo_version = pkg.get("repo_version")
        key = pkg.get("key")

        if repo and repo_version:
            subprocess.run(
                ["sudo", "add-apt-repository", f"deb {repo} {repo_version}", "-y"],
                check=True,
            )

        if key:
            subprocess.run(
                ["sudo", "apt-key", "adv", "--keyserver", "keyserver.ubuntu.com", "--recv-keys", key],
                check=True,
            )

        logger.info(f"Installing {name}...")
        subprocess.run(["sudo", "apt", "install", "-y", name], check=True)

    _run_os_hooks(hooks, "after")

def install_packages_termux(packages: Iterable[PackageConfig], hooks: HookConfig | None) -> None:
    """Install packages on Termux using pkg."""
    packages_to_install: list[PackageConfig] = []
    for pkg in packages:
        name = pkg.get("name")
        if not name:
            continue
        if is_package_installed_termux(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue
        packages_to_install.append(pkg)

    if not packages_to_install:
        logger.info("All packages are already installed; skipping hooks.")
        return

    _run_os_hooks(hooks, "before")

    for pkg in packages_to_install:
        name = pkg.get("name")
        if not name:
            continue

        logger.info(f"Installing {name}...")
        subprocess.run(["pkg", "install", "-y", name], check=True)

    _run_os_hooks(hooks, "after")

def install_packages(packages: Iterable[PackageConfig], hooks: HookConfig | None, os_type: str) -> None:
    """Install packages based on the OS type."""
    if os_type == "gentoo":
        install_packages_gentoo(packages, hooks)
    elif os_type == "arch":
        install_packages_arch(packages, hooks)
    elif os_type == "macos":
        install_packages_macos(packages, hooks)
    elif os_type == "ubuntu":
        install_packages_ubuntu(packages, hooks)
    elif os_type == "termux":
        install_packages_termux(packages, hooks)
    else:
        raise ValueError(f"Unsupported OS: {os_type}")

def os_packages_installer(os_type: str, configs: Iterable[ToolConfig]) -> None:
    flag_install_is_essential_only = os.environ.get("FLAG_INSTALL_IS_ESSENTIAL_ONLY")

    update_repositories(os_type)

    for config in configs:
        is_essential = config.get("is_essential", False)
        if flag_install_is_essential_only and not is_essential:
            continue

        logger.info(f"Processing configuration: {config.get('name')}")
        os_config = config.get(os_type)
        if not isinstance(os_config, dict):
            logger.warning(f"No package configuration found for OS: {os_type}")
            continue

        packages = os_config.get("packages", [])
        hooks = os_config.get("hook", {})

        if not packages:
            logger.warning(f"No packages to install for OS: {os_type}")
            continue

        install_packages(packages, hooks, os_type)
        logger.info("Package installation completed successfully.")

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

def main(argv: list[str], *, detected_os: str) -> int:
    try:
        args = _parse_args(argv)
        if args.essential_only:
            os.environ["FLAG_INSTALL_IS_ESSENTIAL_ONLY"] = "true"

        all_tools: list[ToolConfig] = load_all_tools()
        tools = [tool for tool in all_tools if tool and tool.get("method") == "os"]

        tool_name = args.tool or args.tool_positional
        if tool_name:
            tools = [tool for tool in tools if tool.get("name") == tool_name]

        if not tools:
            logger.warning(f'No tool with method: "os" found with name: "{tool_name or ""}"')
            return 0

        os_packages_installer(detected_os, tools)
        return 0
    except subprocess.CalledProcessError as exc:
        logger.error(f"Failed to install packages: {exc}")
        return 1
    except Exception as exc:
        logger.error(str(exc))
        return 1

def cli() -> None:
    os_info = get_os_info()
    logger.info(f"Detected OS: {os_info.get('name')}")
    raise SystemExit(main(sys.argv, detected_os=os_info.get("shortCode")))

if __name__ == "__main__":
    cli()
