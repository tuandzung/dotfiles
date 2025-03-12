from logger import logger
import subprocess
import os

def run_hook(hook_commands):
    """Run a hook by executing the specified commands."""
    if not hook_commands:
        return

    logger.info("Running hook...")
    os.system(hook_commands)

def handle_version_tags(s, version):
    ret_s = s
    if s.find("%1s") != -1:
        ret_s = s.replace("%1s", "v%s") % version
    elif s.find("%s") != -1:
        ret_s = s % version
    return ret_s
