"""B5 command adapter; protocol validation remains in the original receiver."""
from pathlib import Path
from typing import Any

from ..config import build_command
from .process_runner import ProcessRunner


def b5_command(parameters: dict[str, Any], output_dir: Path) -> list[str]:
    return build_command("B5", parameters, output_dir)


class B5Runner(ProcessRunner):
    """A ProcessRunner with a convenient fixed-mode entry point."""

    def run(self, parameters: dict[str, Any], output_dir: Path) -> bool:
        return self.start("B5", parameters, output_dir)
