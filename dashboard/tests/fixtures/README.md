# Synthetic dashboard fixtures

Everything in this directory is **SIMULATED TEST DATA**, not FPGA board evidence.
The replay service produces the original CLI grammar with source `REPLAY`, and
creates B5 length-prefixed fixture captures using the existing pure packet
constructors without calling their socket/CLI entry points.

The B6 fixture intentionally starts Data at round 14, Version at count 3 and
Context at count 7. It demonstrates independent sequences and a 15 → 0 wrap.
Default replay has 1 Version, 1 Context and 20 Data records; changing B6 selected
types and rounds changes the emitted evidence and statistics.
