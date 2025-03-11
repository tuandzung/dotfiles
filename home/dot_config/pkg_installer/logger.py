import logging
import colorlog

# Set up colored logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Create a colored formatter
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

# Create a console handler and set the formatter
console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)

# Add handlers to the logger
logger.addHandler(console_handler)
