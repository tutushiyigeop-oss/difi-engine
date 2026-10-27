# DIFI Engine Control Center

Windows PySide6 + pyqtgraph application for the independent B5 (FPGA → PC) and B6 (PC → FPGA) UDP validation flows.

## Install

From the repository root, using Python 3.11+ on Windows:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r dashboard/requirements.txt
.\.venv\Scripts\python.exe dashboard/main.py
```

Alternatively launch `dashboard/launch_dashboard.bat`. Dependencies must not be installed into Vivado/Vitis Python.

## Modes

- **Replay / Offline**: inspect saved/sample B5 and B6 sessions without sending network traffic.
- **Live / Hardware**: select B5 UDP TX or B6 UDP RX, configure the actual board/PC IP addresses, UDP port, and timeout, prepare the corresponding board hardware and firmware, then click Run.
- **B5**: load the B5 raw-packet-export design and matching `vitis/vitis_ws/difi_b5_udp_tx` application. Initialize UTC on UART before beginning. Receiver: `scripts/verify/tools/difi_udp_receiver.py`.
- **B6**: load the B6 UDP-RX design and matching `vitis/vitis_ws/difi_b6_udp_rx_pro` application. Sender: `scripts/verify/tools/difi_b6_three_types.py`.

B5 and B6 are **separate bitstream/XSA/ELF configurations**, not simultaneous full duplex. The application does not program the FPGA or load an ELF. Match the current hardware image and software before using Live mode.

Use the packet timeline, metadata, error events, IQ verification, waveform viewer, and session export to inspect the run. Exported Replay results are not evidence of a new hardware run.

## Testing

```powershell
.\.venv\Scripts\python.exe -m pytest dashboard/tests
```

The B5/B6 UI is the maintained demonstration path. See the repository root README for hardware evidence, reference validation, and reproduction limits.
