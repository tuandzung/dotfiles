from __future__ import annotations

import logging

try:
    import colorlog  # type: ignore
except ModuleNotFoundError:  # pragma: no cover
    colorlog = None

# Set up colored logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

if colorlog is not None:
    formatter = colorlog.ColoredFormatter(
        "%(log_color)s%(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        log_colors={
            "DEBUG": "cyan",
            "INFO": "green",
            "WARNING": "yellow",
            "ERROR": "red",
            "CRITICAL": "red,bg_white",
        },
    )
else:
    formatter = logging.Formatter("%(levelname)s - %(message)s")

# Create a console handler and set the formatter
console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)

# Add handlers to the logger (avoid duplicates on repeated imports)
if not any(isinstance(h, logging.StreamHandler) for h in logger.handlers):
    logger.addHandler(console_handler)
