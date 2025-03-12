import yaml
import subprocess
import platform
import sys
import os
from logger import logger
from utils import run_hook

def detect_os():
    """Detect the current operating system."""
    system = platform.system().lower()
    if system == "linux":
        # Detect Linux distribution
        with open("/etc/os-release", "r") as f:
            for line in f:
                if line.startswith("ID="):
                    return line.strip().split("=")[1].strip('"')
    elif system == "darwin":
        return "macos"
    elif system == "android":
        return "termux"
    return system

def update_repositories(os_type):
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

def is_package_installed_gentoo(package_name):
    """Check if a package is installed on Gentoo."""
    result = subprocess.run(["qlist", "-I", package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def is_package_installed_arch(package_name):
    """Check if a package is installed on Arch Linux."""
    result = subprocess.run(["pacman", "-Qi", package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def is_package_installed_macos(package_name, cask=False):
    """Check if a package is installed on macOS."""
    if cask:
        result = subprocess.run(["brew", "list", "--cask", package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    else:
        result = subprocess.run(["brew", "list", package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def is_package_installed_ubuntu(package_name):
    """Check if a package is installed on Ubuntu."""
    result = subprocess.run(["dpkg", "-s", package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def is_package_installed_termux(package_name):
    """Check if a package is installed on Termux."""
    result = subprocess.run(["pkg", "list-installed", package_name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.returncode == 0

def install_packages_gentoo(packages, hooks):
    # Run before-install hook if specified
    if hooks and "before" in hooks:
        run_hook(hooks["before"])

    """Install packages on Gentoo using emerge, handle package.use, and add overlays."""
    for pkg in packages:
        name = pkg.get("name")
        repo = pkg.get("repo")
        accept_keywords = pkg.get("accept_keywords", "")
        use_flags = pkg.get("use", "")
        base_name = name.split("/")[1]

        # Check if the package is already installed
        if is_package_installed_gentoo(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue

        if repo:
            # Add and enable the overlay
            logger.info(f"Adding and enabling overlay: {repo}...")
            subprocess.run(["sudo", "eselect", "repository", "enable", repo], check=True)
            subprocess.run(["sudo", "emerge", "--sync", repo], check=True)
            name = f"{name}::{repo}"

        if accept_keywords:
            # Set ACCEPT_KEYWORDS for the package
            accept_keywords_path = f"/etc/portage/package.accept_keywords/{base_name}"
            subprocess.run([
                "sudo", "mkdir", "-p", os.path.dirname(accept_keywords_path)
            ], check=True)
            subprocess.run([
                "sudo", "touch", accept_keywords_path
            ], check=True)
            echo_cmd = subprocess.run(["echo", accept_keywords], check=True, capture_output=True)
            subprocess.run(["sudo", "tee", accept_keywords_path], input=echo_cmd.stdout, check=True)

        if use_flags:
            # Append USE flags to package.use
            use_flags_path = f"/etc/portage/package.use/{base_name}"
            subprocess.run([
                "sudo", "mkdir", "-p", os.path.dirname(use_flags_path)
            ], check=True)
            subprocess.run([
                "sudo", "touch", use_flags_path
            ], check=True)
            echo_cmd = subprocess.run(["echo", use_flags], check=True, capture_output=True)
            subprocess.run(["sudo", "tee", use_flags_path], input=echo_cmd.stdout, check=True)

        # Install the package (non-interactively)
        logger.info(f"Installing {name}...")
        subprocess.run([
            "sudo", "emerge", "--ask", "n", "--quiet-build", "--noreplace", name
        ], check=True)

    # Run after-install hook if specified
    if hooks and "after" in hooks:
        run_hook(hooks["after"])

def install_packages_arch(packages, hooks):
    # Run before-install hook if specified
    if hooks and "before" in hooks:
        run_hook(hooks["before"])

    """Install packages on Arch Linux using pacman."""
    for pkg in packages:
        name = pkg.get("name")

        # Check if the package is already installed
        if is_package_installed_arch(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue

        logger.info(f"Installing {name}...")
        subprocess.run(["yay", "-S", "--noconfirm", "--needed", "--answerclean", "All", "--answerdiff", "None", name], check=True)

    # Run after-install hook if specified
    if hooks and "after" in hooks:
        run_hook(hooks["after"])

def install_packages_macos(packages, hooks):
    # Run before-install hook if specified
    if hooks and "before" in hooks:
        run_hook(hooks["before"])

    """Install packages on macOS using Homebrew and Homebrew Cask."""
    for pkg in packages:
        name = pkg.get("name")
        cask = pkg.get("cask", False)  # Check if this is a Cask package

        # Check if the package is already installed
        if is_package_installed_macos(name, cask):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue

        if cask:
            logger.info(f"Installing Cask package: {name}...")
            subprocess.run(["brew", "install", "--cask", name], check=True)
        else:
            logger.info(f"Installing Homebrew package: {name}...")
            subprocess.run(["brew", "install", name], check=True)

    # Run after-install hook if specified
    if hooks and "after" in hooks:
        run_hook(hooks["after"])

def install_packages_ubuntu(packages, hooks):
    # Run before-install hook if specified
    if hooks and "before" in hooks:
        run_hook(hooks["before"])

    """Install packages on Ubuntu using apt."""
    for pkg in packages:
        name = pkg.get("name")
        repo = pkg.get("repo")
        repo_version = pkg.get("repo_version")
        key = pkg.get("key")

        # Check if the package is already installed
        if is_package_installed_ubuntu(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue

        if repo and repo_version:
            # Add the repository
            subprocess.run(["sudo", "add-apt-repository", f"deb {repo} {repo_version}", "-y"], check=True)

        if key:
            # Add the repository key
            subprocess.run(["sudo", "apt-key", "adv", "--keyserver", "keyserver.ubuntu.com", "--recv-keys", key], check=True)

        # Install the package
        logger.info(f"Installing {name}...")
        subprocess.run(["sudo", "apt", "install", "-y", name], check=True)

    # Run after-install hook if specified
    if hooks and "after" in hooks:
        run_hook(hooks["after"])

def install_packages_termux(packages, hooks):
    # Run before-install hook if specified
    if hooks and "before" in hooks:
        run_hook(hooks["before"])

    """Install packages on Termux using pkg."""
    for pkg in packages:
        name = pkg.get("name")
        logger.info(f"Installing package {name}...")

        # Check if the package is already installed
        if is_package_installed_termux(name):
            logger.info(f"Package {name} is already installed. Skipping...")
            continue

        logger.info(f"Installing {name}...")
        subprocess.run(["pkg", "install", "-y", name], check=True)

    # Run after-install hook if specified
    if hooks and "after" in hooks:
        run_hook(hooks["after"])

def install_packages(packages, hooks, os_type):
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

def os_packages_installer(os_type, configs):
    # Update repositories once at the start
    update_repositories(os_type)

    # Process each configuration in the YAML file
    for config in configs:
        is_essential = config.get("is_essential", False)
        if is_essential:
            logger.info(f"Processing configuration: {config.get('name')}")

            # Get the package list and hooks for the detected OS
            if os_type not in config:
                logger.warning(f"No package configuration found for OS: {os_type}")
                continue

            packages = config[os_type].get("packages", [])
            hooks = config[os_type].get("hook", {})

            if not packages:
                logger.warning(f"No packages to install for OS: {os_type}")
                continue

            # Install the packages
            try:
                install_packages(packages, hooks, os_type)
                logger.info("Package installation completed successfully.")
            except subprocess.CalledProcessError as e:
                logger.error(f"Failed to install packages: {e}")
                sys.exit(1)

def main(yaml_file):
    # Load the YAML file as a multi-document file
    with open(yaml_file, "r") as f:
        configs = list(yaml.safe_load_all(f))

    # Detect the current OS
    os_type = detect_os()
    logger.info(f"Detected OS: {os_type}")

    # Update repositories once at the start
    # update_repositories(os_type)

    # Process each configuration in the YAML file
    for config in configs:
        logger.info(f"\nProcessing configuration: {config.get('name')}")

        # Get the package list and hooks for the detected OS
        if os_type not in config:
            logger.warning(f"No package configuration found for OS: {os_type}")
            continue

        packages = config[os_type].get("packages", [])
        hooks = config[os_type].get("hook", {})

        if not packages:
            logger.warning(f"No packages to install for OS: {os_type}")
            continue

        # Install the packages
        logger.warning(f"Installing packages for {os_type}...")
        try:
            install_packages(packages, hooks, os_type)
            logger.info("Package installation completed successfully.")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to install packages: {e}")
            sys.exit(1)

if __name__ == "__main__":
    # if len(sys.argv) != 2:
    #     logger.info("Usage: python install_packages.py <yaml_file>")
    #     sys.exit(1)

    # yaml_file = sys.argv[1]
    # main(yaml_file)
    pass
