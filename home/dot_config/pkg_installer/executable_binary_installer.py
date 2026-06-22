from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import sys
import tempfile
from base64 import b64encode
from collections.abc import Callable, Iterable, Iterator, Mapping
from dataclasses import dataclass
from functools import wraps
from pathlib import Path
from typing import Any, NotRequired, TypedDict
from urllib.parse import quote_plus

from logger import logger
from utils import handle_version_tags, load_all_tools, run_hook

try:
    import patoolib  # type: ignore
except ModuleNotFoundError:  # pragma: no cover
    patoolib = None

try:
    import requests  # type: ignore
except ModuleNotFoundError:  # pragma: no cover
    requests = None

try:
    from tqdm import tqdm  # type: ignore
except ModuleNotFoundError:  # pragma: no cover
    tqdm = None

class ToolHook(TypedDict):
    """Hooks to run before and after tool execution."""

    before: str
    after: str

class ToolArchive(TypedDict):
    """Legacy paths to include in the tool archive."""

    paths: list[str]
    strip_components: NotRequired[int]

class ToolArchiveEntry(TypedDict):
    """One archive path install rule."""

    path: str
    strip: NotRequired[int]
    location: NotRequired[str]

class GithubSource(TypedDict):
    """GitHub repository information."""

    repo: str
    release_asset: str
    version: NotRequired[str]
    sha256: NotRequired[str]

class GitlabSource(TypedDict):
    """GitLab repository information."""

    repo: str
    release_asset: str
    version: NotRequired[str]
    host: NotRequired[str]
    sha256: NotRequired[str]

class Tool(TypedDict):
    """Tool information."""

    name: str
    method: str
    is_essential: bool
    hook: ToolHook
    archive: ToolArchive | list[ToolArchiveEntry]
    github: GithubSource
    gitlab: GitlabSource

Provider = str  # "github" | "gitlab"

@dataclass(frozen=True)
class InstallerContext:
    """Context for the installer."""

    install_dir: Path
    man_dir: Path
    temp_dir: Path
    github_auth_header: Mapping[str, str]
    gitlab_token: str | None

_LAST_TEMP_DIR: Path | None = None

def _ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)

def _make_github_auth_header(username: str | None, token: str | None) -> Mapping[str, str]:
    if not username or not token:
        return {}
    credentials = f"{username}:{token}"
    encoded_credentials = b64encode(credentials.encode("utf-8")).decode("utf-8")
    return {"Authorization": f"Basic {encoded_credentials}"}

def _gitlab_headers(gitlab_token: str | None) -> dict[str, str]:
    if not gitlab_token:
        return {}
    return {"PRIVATE-TOKEN": gitlab_token}

def _cleanup_temp_dir(temp_dir: Path) -> None:
    shutil.rmtree(temp_dir, ignore_errors=True)

def _get_latest_release_tag_from_github_api(
    session: requests.Session, tool: Tool, github_auth_header: Mapping[str, str]
) -> str:
    repo = tool["github"]["repo"]
    github_api_url = f"https://api.github.com/repos/{repo}/releases/latest"
    response = session.get(github_api_url, headers=github_auth_header)
    if response.status_code != 200:
        raise RuntimeError(f"Failed to fetch GitHub release information: {response.status_code}")
    release_info = response.json()
    tag_name = release_info.get("tag_name")
    if not isinstance(tag_name, str) or not tag_name:
        raise RuntimeError("Unexpected GitHub release payload")
    return tag_name

def _get_latest_release_tag_from_gitlab_api(
    session: requests.Session, tool: Tool, gitlab_token: str | None
) -> str:
    gitlab = tool["gitlab"]
    repo = gitlab["repo"]
    host = gitlab.get("host", "https://gitlab.com").rstrip("/")

    releases_url = f"{host}/api/v4/projects/{quote_plus(repo, safe='')}/releases"
    params = {"per_page": 1, "order_by": "released_at", "sort": "desc"}
    response = session.get(releases_url, headers=_gitlab_headers(gitlab_token), params=params)
    if response.status_code != 200:
        raise RuntimeError(f"Failed to fetch GitLab release information: {response.status_code}")

    release_info = response.json()
    if isinstance(release_info, list) and release_info:
        tag_name = release_info[0].get("tag_name")
        if isinstance(tag_name, str) and tag_name:
            return tag_name
    raise RuntimeError("Unexpected GitLab release payload")

def _with_hooks(func: Callable[..., None], tool: Tool, version: str) -> Callable[..., None]:
    @wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> None:
        hook_before = tool.get("hook", {}).get("before")
        hook_after = tool.get("hook", {}).get("after")

        if hook_before:
            run_hook(handle_version_tags(hook_before, version))

        func(*args, **kwargs)

        if hook_after:
            run_hook(handle_version_tags(hook_after, version))

    return wrapper

def _make_executable(path: Path) -> None:
    path.chmod(path.stat().st_mode | 0o111)

def _resolve_archive_location(location: str | None, version: str, install_dir: Path) -> Path:
    if not location:
        return install_dir

    resolved = handle_version_tags(location, version)
    resolved = os.path.expandvars(resolved)
    return Path(resolved).expanduser()


def _ensure_destination_under_location(dest_path: Path, location: Path) -> None:
    resolved_dest = dest_path.resolve(strict=False)
    resolved_location = location.resolve(strict=False)
    if not resolved_dest.is_relative_to(resolved_location):
        raise RuntimeError(f"Archive destination escapes location: {dest_path}")


def _move_installed_file(src_path: Path, dest_path: Path, *, make_executable: bool) -> None:
    if dest_path.exists():
        if dest_path.is_dir():
            raise RuntimeError(f"Archive destination is a directory: {dest_path}")
        dest_path.unlink()

    _ensure_dir(dest_path.parent)
    shutil.move(str(src_path), str(dest_path))
    if make_executable:
        _make_executable(dest_path)
    logger.info(f"Installed {src_path.name} to {dest_path}")


def _install_legacy_archive_paths(
    archive: ToolArchive,
    version: str,
    *,
    temp_dir: Path,
    install_dir: Path,
) -> None:
    for rel_path in archive["paths"]:
        resolved = handle_version_tags(rel_path, version)
        src_path = temp_dir / resolved
        dest_path = install_dir / Path(resolved).name
        _move_installed_file(src_path, dest_path, make_executable=True)


def _install_archive_entry(
    entry: ToolArchiveEntry,
    version: str,
    *,
    temp_dir: Path,
    install_dir: Path,
) -> None:
    path_pattern = handle_version_tags(entry["path"], version)
    strip_components = int(entry.get("strip", 0))
    if strip_components < 0:
        raise RuntimeError(f"Archive strip must be non-negative for {path_pattern}")

    location = _resolve_archive_location(entry.get("location"), version, install_dir)
    make_executable = location.resolve(strict=False) == install_dir.resolve(strict=False)

    matched_files = sorted(
        path for path in temp_dir.glob(path_pattern)
        if path.is_file() and path.resolve(strict=False).is_relative_to(temp_dir.resolve(strict=False))
    )
    if not matched_files:
        raise RuntimeError(f"No archive files matched {path_pattern}")

    for src_path in matched_files:
        relative_parts = src_path.relative_to(temp_dir).parts
        if strip_components >= len(relative_parts):
            raise RuntimeError(f"Archive strip removes entire path for {path_pattern}")

        relative_dest = Path(*relative_parts[strip_components:])
        dest_path = location / relative_dest
        _ensure_destination_under_location(dest_path, location)
        _move_installed_file(src_path, dest_path, make_executable=make_executable)


def _install_archive_paths(
    archive: ToolArchive | list[ToolArchiveEntry],
    version: str,
    *,
    temp_dir: Path,
    install_dir: Path,
) -> None:
    if isinstance(archive, list):
        for entry in archive:
            _install_archive_entry(entry, version, temp_dir=temp_dir, install_dir=install_dir)
        return

    _install_legacy_archive_paths(archive, version, temp_dir=temp_dir, install_dir=install_dir)


def _extract_and_install_archive(
    tool: Tool,
    release_tag: str,
    release_asset: str,
    asset_path: Path,
    *,
    temp_dir: Path,
    install_dir: Path,
) -> None:
    if patoolib is None:
        raise RuntimeError('Missing dependency: "patool" (patoolib)')

    logger.info(f"Extracting {asset_path}...")
    try:
        patoolib.extract_archive(str(asset_path), outdir=str(temp_dir))
        version = release_tag.removeprefix("v")
        _install_archive_paths(
            tool["archive"],
            version,
            temp_dir=temp_dir,
            install_dir=install_dir,
        )
    except patoolib.util.PatoolError as e:
        logger.error(f"Failed to extract {release_asset}: {e}")

def _download_asset(
    session: requests.Session,
    asset_url: str,
    release_asset: str,
    *,
    headers: Mapping[str, str],
    destination_dir: Path,
) -> Path:
    if tqdm is None:
        raise RuntimeError('Missing dependency: "tqdm"')

    asset_path = destination_dir / release_asset
    logger.info(f"Downloading {release_asset}...")
    response = session.get(asset_url, headers=headers, stream=True)
    if response.status_code != 200:
        raise RuntimeError(f"Failed to download {release_asset}: {response.status_code}")

    total_size = int(response.headers.get("content-length", 0))
    block_size = 1024  # 1 KB
    with asset_path.open("wb") as file_handle:
        with tqdm(total=total_size, unit="B", unit_scale=True, desc=release_asset) as pbar:
            for data in response.iter_content(block_size):
                file_handle.write(data)
                pbar.update(len(data))

    logger.info(f"Successfully downloaded {release_asset}")
    return asset_path

def _build_release_download_url(
    provider: Provider,
    source: Mapping[str, Any],
    release_tag: str,
    filename: str,
) -> str:
    repo = source["repo"]
    if provider == "github":
        return f"https://github.com/{repo}/releases/download/{release_tag}/{filename}"

    host = str(source.get("host", "https://gitlab.com")).rstrip("/")
    return f"{host}/{repo}/-/releases/{release_tag}/downloads/{filename}"


def _find_expected_sha256(checksum_path: Path, release_asset: str) -> str:
    digest_pattern = re.compile(r"^[0-9a-fA-F]{64}$")
    for line in checksum_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        parts = stripped.split(maxsplit=1)
        if len(parts) != 2:
            continue

        digest, filename = parts
        filename = filename.lstrip("*")
        if Path(filename).name != release_asset:
            continue

        if not digest_pattern.fullmatch(digest):
            raise RuntimeError(f"Malformed SHA256 digest for {release_asset}: {digest}")
        return digest.lower()

    raise RuntimeError(f"No SHA256 checksum found for {release_asset} in {checksum_path.name}")


def _calculate_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_handle:
        for chunk in iter(lambda: file_handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_sha256(asset_path: Path, checksum_path: Path, release_asset: str) -> None:
    expected_digest = _find_expected_sha256(checksum_path, release_asset)
    actual_digest = _calculate_sha256(asset_path)
    if actual_digest != expected_digest:
        raise RuntimeError(
            f"SHA256 mismatch for {release_asset}: expected {expected_digest}, got {actual_digest}"
        )
    logger.info(f"Verified SHA256 for {release_asset}")


def _select_source(tool: Tool) -> tuple[Provider, Mapping[str, Any]]:
    if tool.get("github"):
        return "github", tool["github"]
    if tool.get("gitlab"):
        return "gitlab", tool["gitlab"]
    raise KeyError("No supported source defined (github/gitlab)")

def _iter_binary_tools(all_tools: Iterable[Tool]) -> Iterator[Tool]:
    for tool in all_tools:
        if tool and tool.get("method") == "binary":
            yield tool

def binaries_installer(tools: Iterable[Tool], *, ctx: InstallerContext | None = None) -> None:
    flag_install_is_essential_only = os.environ.get("FLAG_INSTALL_IS_ESSENTIAL_ONLY")
    flag_install_not_exists_only = os.environ.get("FLAG_INSTALL_NOT_EXISTS_ONLY")

    own_ctx = ctx is None
    ctx = _build_context() if ctx is None else ctx
    try:
        with requests.Session() as session:
            for tool in tools:
                name = tool["name"]
                is_essential = tool.get("is_essential", False)
                if flag_install_not_exists_only and (ctx.install_dir / name).is_file():
                    logger.info(f"{name} is already installed, skipping...")
                    continue

                if flag_install_is_essential_only and not is_essential:
                    logger.info(f"{name} is not an essential tool, skipping...")
                    continue

                try:
                    provider, source = _select_source(tool)
                except KeyError:
                    logger.error(f"No supported source defined for {name} (github/gitlab)")
                    continue

                download_version = source.get("version")
                if download_version in (None, "latest"):
                    if provider == "github":
                        release_tag = _get_latest_release_tag_from_github_api(
                            session, tool, ctx.github_auth_header
                        )
                    else:
                        release_tag = _get_latest_release_tag_from_gitlab_api(session, tool, ctx.gitlab_token)
                else:
                    release_tag = str(download_version)
                version = release_tag.removeprefix("v")

                release_asset = handle_version_tags(source["release_asset"], version)
                asset_url = _build_release_download_url(provider, source, release_tag, release_asset)

                if provider == "github":
                    download_headers = ctx.github_auth_header
                else:
                    download_headers = _gitlab_headers(ctx.gitlab_token)

                asset_path = _download_asset(
                    session,
                    asset_url,
                    release_asset,
                    headers=download_headers,
                    destination_dir=ctx.temp_dir,
                )

                checksum_asset = source.get("sha256")
                if checksum_asset:
                    checksum_asset = handle_version_tags(str(checksum_asset), version)
                    checksum_url = _build_release_download_url(provider, source, release_tag, checksum_asset)
                    checksum_path = _download_asset(
                        session,
                        checksum_url,
                        checksum_asset,
                        headers=download_headers,
                        destination_dir=ctx.temp_dir,
                    )
                    _verify_sha256(asset_path, checksum_path, release_asset)

                os.environ["RELEASE_ASSET"] = release_asset

                archive = tool.get("archive", {})
                if not archive:
                    dest_path = ctx.install_dir / name
                    shutil.move(str(asset_path), str(dest_path))
                    _make_executable(dest_path)
                    logger.info(f"Installed {name} to {dest_path}")
                else:
                    _with_hooks(_extract_and_install_archive, tool, version)(
                        tool,
                        release_tag,
                        release_asset,
                        asset_path,
                        temp_dir=ctx.temp_dir,
                        install_dir=ctx.install_dir,
                    )
                    logger.info(f"Successfully extracted and installed {release_asset}\n")
    finally:
        if own_ctx:
            _cleanup_temp_dir(ctx.temp_dir)

def _build_context() -> InstallerContext:
    global _LAST_TEMP_DIR
    install_dir = Path("~/.local/bin").expanduser()
    man_dir = Path("~/.local/man").expanduser()
    temp_dir = Path(tempfile.mkdtemp())
    _LAST_TEMP_DIR = temp_dir
    _ensure_dir(install_dir)
    _ensure_dir(man_dir)

    os.environ["INSTALL_DIR"] = str(install_dir)
    os.environ["MAN_DIR"] = str(man_dir)
    os.environ["TEMP_DIR"] = str(temp_dir)

    github_username = os.getenv("GITHUB_USERNAME") or os.getenv("GITHUB_API_USERNAME")
    github_token = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
    gitlab_token = os.getenv("GITLAB_TOKEN")

    return InstallerContext(
        install_dir=install_dir,
        man_dir=man_dir,
        temp_dir=temp_dir,
        github_auth_header=_make_github_auth_header(github_username, github_token),
        gitlab_token=gitlab_token,
    )

def cleanup() -> None:
    """
    Backwards-compatible cleanup hook.

    Historically this module created a global temp dir at import time and callers
    invoked `cleanup()` afterwards. Temp dirs are now per-run; this removes the
    most recent temp dir when available.
    """
    if _LAST_TEMP_DIR is not None:
        _cleanup_temp_dir(_LAST_TEMP_DIR)

def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog=Path(argv[0]).name)
    parser.add_argument(
        "-n",
        "--not-exists-only",
        action="store_true",
        help="Install only tools that are not already installed",
    )
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
    parser.add_argument(
        "-d",
        "--debug",
        action="store_true",
        help="Kept for compatibility; currently unused",
    )
    parser.add_argument("tool_positional", nargs="?", default=None)
    return parser.parse_args(argv[1:])

def main(argv: list[str]) -> int:
    args = _parse_args(argv)

    if args.not_exists_only:
        os.environ["FLAG_INSTALL_NOT_EXISTS_ONLY"] = "true"
    if args.essential_only:
        os.environ["FLAG_INSTALL_IS_ESSENTIAL_ONLY"] = "true"

    if requests is None:
        logger.error('Missing dependency: "requests"')
        return 1

    ctx = _build_context()
    try:
        all_tools = load_all_tools()
        binary_tools = list(_iter_binary_tools(all_tools))

        tool_name = args.tool or args.tool_positional
        if tool_name:
            binary_tools = [tool for tool in binary_tools if tool.get("name") == tool_name]

        if not binary_tools:
            logger.warning(f'No tool with method: "binary" found with name: "{tool_name or ""}"')
            return 0

        binaries_installer(binary_tools, ctx=ctx)
        return 0
    except Exception as exc:
        logger.error(str(exc))
        return 1
    finally:
        _cleanup_temp_dir(ctx.temp_dir)

def cli() -> None:
    raise SystemExit(main(sys.argv))

if __name__ == "__main__":
    cli()
