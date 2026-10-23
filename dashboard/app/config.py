"""Validated dashboard settings and commands for the existing verification tools."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from ipaddress import IPv4Address
from pathlib import Path
import math
import sys
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIRECTORY = REPOSITORY_ROOT / "scripts" / "verify" / "tools"


def normalize_mode(mode: str) -> str:
    value = str(mode).strip().upper()
    if value not in {"B5", "B6"}:
        raise ValueError("Mode must be B5 or B6.")
    return value


def _integer(value: Any, name: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer.")
    try:
        number = int(str(value).strip())
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be an integer.") from exc
    if not minimum <= number <= maximum:
        raise ValueError(f"{name} must be between {minimum} and {maximum}.")
    return number


@dataclass
class DemoConfig:
    board: str = "192.168.1.10"
    local_ip: str = "192.168.1.20"
    port: int = 4991
    timeout: float = 10.0
    types: str = "version,context,data"
    rounds: int = 20

    @classmethod
    def for_mode(cls, mode: str) -> "DemoConfig":
        return cls(timeout=10.0 if normalize_mode(mode) == "B5" else 5.0)

    @classmethod
    def from_dict(cls, parameters: dict[str, Any], mode: str = "B5") -> "DemoConfig":
        defaults = cls.for_mode(mode).to_dict()
        incoming = dict(parameters)
        if "pc_ip" in incoming and "local_ip" not in incoming:
            incoming["local_ip"] = incoming["pc_ip"]
        defaults.update({key: value for key, value in incoming.items() if key in defaults})
        return cls(**defaults).validate(mode)

    def validate(self, mode: str = "B5") -> "DemoConfig":
        normalize_mode(mode)
        for name in ("board", "local_ip"):
            value = str(getattr(self, name)).strip()
            try:
                value = str(IPv4Address(value))
            except (ValueError, TypeError) as exc:
                label = "Board IP" if name == "board" else "PC / Local IP"
                raise ValueError(f"{label} must be a numeric IPv4 address.") from exc
            setattr(self, name, value)
        self.port = _integer(self.port, "UDP port", 1, 65535)
        self.rounds = _integer(self.rounds, "Data rounds", 1, 1000)
        try:
            timeout = float(self.timeout)
        except (TypeError, ValueError) as exc:
            raise ValueError("Timeout must be a positive number of seconds.") from exc
        if isinstance(self.timeout, bool) or not math.isfinite(timeout) or not 0 < timeout <= 3600:
            raise ValueError("Timeout must be greater than 0 and at most 3600 seconds.")
        self.timeout = timeout
        if isinstance(self.types, (list, tuple)):
            types = [str(item).strip().lower() for item in self.types]
        else:
            types = [item.strip().lower() for item in str(self.types).split(",")]
        if not types or len(set(types)) != len(types) or any(
            kind not in {"version", "context", "data"} for kind in types
        ):
            raise ValueError("Types must be a unique comma-separated subset of version,context,data.")
        self.types = ",".join(types)
        return self

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def build_command(mode: str, parameters: dict[str, Any], output_dir: Path) -> list[str]:
    """Build argv only. Creating a command never starts a process or opens a socket."""
    mode = normalize_mode(mode)
    config = DemoConfig.from_dict(parameters, mode)
    script = TOOLS_DIRECTORY / ("difi_udp_receiver.py" if mode == "B5" else "difi_b6_three_types.py")
    args = [sys.executable, "-u", str(script), "--board", config.board,
            "--pc-ip" if mode == "B5" else "--local-ip", config.local_ip,
            "--port", str(config.port), "--timeout", str(config.timeout)]
    if mode == "B5":
        args.extend(["--output", str(Path(output_dir).resolve() / "b5_capture.bin")])
    else:
        args.extend(["--types", config.types, "--rounds", str(config.rounds)])
    return args
