"""B6 command adapter; STATUS/ACK checks remain in the original sender."""
from pathlib import Path
from typing import Any

from ..config import build_command
from .process_runner import ProcessRunner


def b6_command(parameters: dict[str, Any], output_dir: Path) -> list[str]:
    return build_command("B6", parameters, output_dir)


class B6Runner(ProcessRunner):
    """A ProcessRunner with a convenient fixed-mode entry point."""

    def run(self, parameters: dict[str, Any], output_dir: Path) -> bool:
        return self.start("B6", parameters, output_dir)
