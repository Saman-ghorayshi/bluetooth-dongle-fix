# BTFix report

- generated: 2026-10-22T00:11:36.1503841+03:30
- machine: MODEERFONARI
- windows: Microsoft Windows 11 Home 10.0.26300
- classification: **RadioConflictOrDriverStartFailure** (confidence High)

## Radios

| radio | status | code | driver | internal |
| --- | --- | --- | --- | --- |
| Realtek Bluetooth Adapter | Error | 31 |  1.9.1051.3004 | True |
| Generic Bluetooth Radio | OK | 0 |  10.0.26100.9711 | False |

## Evidence

- Radio 'Realtek Bluetooth Adapter' (USB\VID_0BDA&PID_4853\00E04C000001) fails with Code 31 (CM_PROB_FAILED_ADD).
- Another radio (Generic Bluetooth Radio) currently holds the Bluetooth stack.

## Recommended actions

- Disable the other radio, re-scan, and let the stack settle on the dongle.

## Services

- BTAGService: Running (Manual)
- bthserv: Running (Manual)

