import os
import requests
import patoolib
import shutil
import tempfile
from tqdm import tqdm
from base64 import b64encode
from functools import wraps
from logger import logger
from utils import run_hook, handle_version_tags

# Directory to install binaries
INSTALL_DIR = os.path.expanduser("~/.local/bin")
os.makedirs(INSTALL_DIR, exist_ok=True)
os.environ["INSTALL_DIR"] = INSTALL_DIR

# Directory to save the downloaded files
TEMP_DIR = tempfile.mkdtemp()
os.environ["TEMP_DIR"] = TEMP_DIR

MAN_DIR = os.path.expanduser("~/.local/man")
os.environ["MAN_DIR"] = MAN_DIR
os.makedirs(MAN_DIR, exist_ok=True)

GITHUB_USERNAME = os.getenv("GITHUB_USERNAME")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")

# Encode credentials for Basic Authentication
CREDENTIALS = f"{GITHUB_USERNAME}:{GITHUB_TOKEN}"
ENCODED_CREDENTIALS = b64encode(CREDENTIALS.encode("utf-8")).decode("utf-8")
AUTH_HEADER = {"Authorization": f"Basic {ENCODED_CREDENTIALS}"}


def cleanup():
    shutil.rmtree(TEMP_DIR)


def __get_latest_release_tag_from_github_api(tool):
    repo = tool["github"]["repo"]

    # GitHub repository details
    github_api_url = f"https://api.github.com/repos/{repo}/releases/latest"

    # Fetch the latest release information
    response = requests.get(github_api_url, headers=AUTH_HEADER)
    if response.status_code != 200:
        logger.error(f"Failed to fetch release information: {response.status_code}")
        exit(1)

    release_info = response.json()

    return release_info["tag_name"]


def __hook_wrapper(f, tool, version):
    @wraps(f)
    def wrapper(*args, **kwargs):
        hook_before = tool.get("hook", {}).get("before", None)
        hook_after = tool.get("hook", {}).get("after", None)

        if hook_before:
            hook_before = handle_version_tags(hook_before, version)
            run_hook(hook_before)

        f(*args, **kwargs)

        if hook_after:
            hook_after = handle_version_tags(hook_after, version)
            run_hook(hook_after)

    return wrapper


def __extract_and_install(tool, release_tag, release_assets, asset_path):
    logger.info(f"Extracting {asset_path}...")
    try:
        patoolib.extract_archive(asset_path, outdir=TEMP_DIR)

        # Move binaries to ~/.local/bin
        tool_paths = tool["archive"]["paths"]
        version = release_tag.replace("v", "")
        for path in tool_paths:
            path = handle_version_tags(path, version)
            src_path = os.path.join(TEMP_DIR, path)
            bin_file = os.path.basename(path)
            dest_path = os.path.join(INSTALL_DIR, bin_file)
            shutil.move(src_path, dest_path)
            os.chmod(dest_path, os.stat(dest_path).st_mode | 0o111)
            logger.info(f"Installed {bin_file} to {dest_path}")
    except patoolib.util.PatoolError as e:
        logger.error(f"Failed to extract {release_assets}: {e}")


def binaries_installer(tools):
    for tool in tools:
        name = tool["name"]
        is_essential = tool.get("is_essential", False)
        flag_dont_install_is_essential = os.environ.get("FLAG_IS_ESSENTIAL", True)
        flag_dont_install_exists = os.environ.get("FLAG_INSTALL_EXISTS", True)

        if flag_dont_install_exists and os.path.isfile(f"{INSTALL_DIR}/{name}"):
            logger.info(f"{name} is already installed, skipping...")
            continue

        if flag_dont_install_is_essential and not is_essential:
            logger.info(f"{name} is not an essential tool, skipping...")
            continue

        download_version = tool["github"].get("version", None)
        release_tag = download_version
        if download_version == "latest" or download_version is None:
            release_tag = __get_latest_release_tag_from_github_api(tool)
        version = release_tag.replace("v", "")

        repo = tool["github"]["repo"]
        release_assets = tool["github"]["release_asset"]
        release_assets = handle_version_tags(release_assets, version)

        # Download asset
        asset_url = f"https://github.com/{repo}/releases/download/{release_tag}/{release_assets}"
        asset_path = os.path.join(TEMP_DIR, release_assets)

        logger.info(f"Downloading {release_assets}...")
        response = requests.get(asset_url, headers=AUTH_HEADER, stream=True)
        if response.status_code != 200:
            logger.error(f"Failed to download {release_assets}: {response.status_code}")

        total_size = int(response.headers.get("content-length", 0))
        block_size = 1024  # 1 KB
        with open(asset_path, "wb") as f:
            with tqdm(total=total_size, unit="B", unit_scale=True, desc=release_assets) as pbar:
                for data in response.iter_content(block_size):
                    f.write(data)
                    pbar.update(len(data))

        logger.info(f"Successfully downloaded {release_assets}")
        os.environ["RELEASE_ASSET"] = release_assets

        archive = tool.get("archive", {})
        if not archive:
            src_path = os.path.join(TEMP_DIR, release_assets)
            dest_path = os.path.join(INSTALL_DIR, name)
            shutil.move(src_path, dest_path)
            os.chmod(dest_path, os.stat(dest_path).st_mode | 0o111)
            logger.info(f"Installed {name} to {dest_path}")
        else:
            __hook_wrapper(__extract_and_install, tool, version)(
                tool,
                release_tag,
                release_assets,
                asset_path
            )

        logger.info(f"Successfully extracted and installed {release_assets}\n")
