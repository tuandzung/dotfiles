import os
import requests
import patoolib
import shutil
import tempfile
from tqdm import tqdm
from base64 import b64encode
from functools import wraps
from logger import logger

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


def __run_hook(f, tool, version, name):
    @wraps(f)
    def wrapper(*args, **kwargs):
        hook_before = tool.get("hook", {}).get("before", None)
        hook_after = tool.get("hook", {}).get("after", None)

        if hook_before:
            if hook_before.find("v%s") != -1 or hook_before.find("%s") != -1:
                hook_before = hook_before.replace("v", "") % version
            logger.info(f"Running hook before install {name}")
            os.system(hook_before)

        f(*args, **kwargs)

        if hook_after:
            if hook_after.find("v%s") != -1 or hook_after.find("%s") != -1:
                hook_after = hook_after.replace("v", "") % version
            logger.info(f"Running hook after install {name}")
            os.system(hook_after)

    return wrapper


def __extract_and_install(tool, release_tag, release_assets, asset_path):
    logger.info(f"Extracting {asset_path}...")
    try:
        patoolib.extract_archive(asset_path, outdir=TEMP_DIR)

        # Move binaries to ~/.local/bin
        tool_paths = tool["archive"]["paths"]
        for path in tool_paths:
            if path.find("v%s") != -1 or path.find("%s") != -1:
                version = release_tag.replace("v", "")
                path = path % version

            src_path = os.path.join(TEMP_DIR, path)
            bin_file = os.path.basename(path)
            dest_path = os.path.join(INSTALL_DIR, bin_file)
            shutil.move(src_path, dest_path)
            logger.info(f"Installed {bin_file} to {dest_path}")
    except patoolib.util.PatoolError as e:
        logger.error(f"Failed to extract {release_assets}: {e}")


def binaries_installer(tool):
    name = tool["name"]
    download_version = tool["github"].get("version", None)
    release_tag = download_version
    if download_version == "latest" or download_version is None:
        release_tag = __get_latest_release_tag_from_github_api(tool)
    version = release_tag.replace("v", "")

    repo = tool["github"]["repo"]
    release_assets = tool["github"]["release_asset"]
    if release_assets.find("v%s") != -1 or release_assets.find("%s") != -1:
        release_assets = tool["github"]["release_asset"] % version

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

    __run_hook(__extract_and_install, tool, version, name)(
        tool,
        release_tag,
        release_assets,
        asset_path
    )

    logger.info(f"Successfully extracted and installed {release_assets}\n")
