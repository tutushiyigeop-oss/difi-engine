# Recovered AI chat records

Two ChatGPT conversations were exported as PDF by the developer on 2026-10-27. This directory contains searchable text extracted from those PDFs, with page markers, conversation order, original dialogue, and only limited local-path/host-name redactions. **Both original binary PDF files are committed in [original/](original/).** Their Git blob IDs match the bytes of the two user-supplied PDFs; original SHA256 values are recorded in the table below.

| Original source | Length | Messages | Original PDF SHA256 | Extract |
|---|---|---|---|---|
| [建立Zynq工程.pdf](original/建立Zynq工程.pdf) | 56 pages | 50 (25 user + 25 assistant) | `0adfe78ce51fdae69ad65f105ed29c61574d80ac52c4db89bffb5c402e480d92` | [zynq_board_chat_extracted.txt](zynq_board_chat_extracted.txt) |
| [编写数据包器 RTL.pdf](original/编写数据包器%20RTL.pdf) | 123 pages | 20 (10 user + 10 assistant) | `426e36204c44cce9e128f967b9906e3ec1baa11a66523f9e7302d44` | [data_packetizer_chat_extracted.txt](data_packetizer_chat_extracted.txt) |

## Page-level evidence map

- **R01 – model's initial full RTL, then human-directed change to step-by-step guidance:** Packetizer PDF pages 1, 19–39, 70–76, 94, 117–123.
- **R02 – `report_clocks` corrects wrong-clock hypothesis to wrong implemented Top:** Zynq PDF pages 13–21.
- **R03 – Vitis CMake error `difi_hello_world.c`, suggested fixes, user UART Stage A PASS:** Zynq PDF pages 27–31.
- **R04 – B1/B2/B3 pasted UART results, then user corrects proposal to skip time/FIFO work:** Zynq PDF pages 43–56.

See [the competition AI collaboration report](../../competition/ai_collaboration_report.md) for the precise context, distinction from retrospective C01–C05, and Skill mapping.

## Limitations and handling

- Original source PDFs are archived under `report/ai_collaboration/transcripts/original/`. The searchable text extracts are for review and cross-reference, not exact source binaries.
- The PDF export timestamps do not establish the time of individual messages; only explicit in-conversation log dates are used.
- Source files contain collapsed/ellipsized messages and image links that may no longer resolve. Text extraction is therefore searchable evidence, not an assertion that every invisible or embedded message was recovered.
- Do not delete wrong initial AI guesses: they are material to the correction trace. Do not claim conversation logs alone demonstrate any particular Git file, bitstream, or independent physical retest.
- Local workstation hostname and absolute path prefixes have been masked in the text files for safer public sharing. The original PDFs contain local machine details and should be privacy-reviewed before making the repository public.
