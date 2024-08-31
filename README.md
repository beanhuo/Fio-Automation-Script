# Fio Automation Script

## Overview

This bash script automates the execution of the `fio` tool for storage benchmarking and system performance analysis. It handles multiple iterations of fio tests and extracts important performance metrics such as **IOPS** and **bandwidth** from the output, saving both the raw and filtered data to log files. The filtered results are saved in a CSV format, making them easy to analyze in Excel or other spreadsheet tools.

## Features

- Automatically runs `fio` based on a job file.
- Logs raw `fio` output to a file.
- Filters and extracts key performance metrics (IOPS, Bandwidth).
- Saves filtered results in CSV format for easy analysis in Excel.
- Supports multiple iterations of the test.
- Checks if the `jq` JSON parser is installed, and provides a fallback parsing method using `grep`, `awk`, and `sed` if `jq` is not available.
- Asks for user confirmation before overwriting existing log files.
- Includes versioning for easy tracking of script versions.

## Prerequisites

- `fio`: The Flexible I/O Tester. You can install it via your package manager:
  ```bash
  sudo apt-get install fio    # On Debian/Ubuntu
  sudo yum install fio        # On CentOS/RHEL

## Mannually use fio
sudo fio -rw=randread -bs=4k --direct=1 --filename=/nvme2/fio.bin --size=10G --numjobs=1 --ioengine=libaio --iodepth=64 -group_reporting -name=randread
sudo fio -rw=read -bs=128k --direct=1 --filename=/dev/nvme0n1 --size=20G --numjobs=1 --ioengine=libaio --iodepth=32 -group_reporting -name=read

## prefill disk example with fio
fio \
  --filename=/dev/md0 \     ## specify your disk
  --direct=1 \
  --size=100% \
  --log_avg_msec=10000 \
  --filename=fio_test_file \
  --ioengine=libaio \
  --name disk_fill \
  --rw=write \
  --bs=128k \
  --iodepth=8
