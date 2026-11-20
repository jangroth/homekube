# NVMe carries a dedicated /storage partition; nodes boot SD first

Each NVMe is 512 MiB boot, 80 GiB root and the rest as `/storage` (`LABEL=storage`), Longhorn's data path, so a full volume cannot exhaust the OS. The EEPROM boot order is `0xf61`: with no SD card the node boots NVMe, and inserting a card plus a power cycle recovers a node that lost Wi-Fi and with it the only remote path. Both are set by `copy_mmc_to_nvme.yml`; changing the layout means re-imaging from SD.

Replaces [Decisions 008, 023, 024](../archive/decisions/DECISIONS-2026-Q2.md).
