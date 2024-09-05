#!/bin/bash

# MIT License
# 
# Copyright (c) [2018] [Bean Huo <beanhuo@outlook.com>]
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#the tool prefers jq, if possible, please install jq:
## sudo apt-get install jq 

# Script Version
script_version="1.0.0"

# Usage: ./fio_script.sh <fio_job_file> <iterations> <base_file_name> [--version]

# Check if user asked for the version
if [ "$1" == "--version" ] || [ "$1" == "-v" ]; then
    echo "auto-fio version $script_version"
    exit 0
fi

# Check if the correct number of arguments is provided
if [ $# -lt 3 ]; then
    echo "auto-fio version $script_version"
    echo "Usage: $0 <fio_job_file> <iterations> <base_file_name> [<output_folder>]"
    exit 1
fi

fio_job_file=$1
iterations=$2
base_file_name=$3
output_folder=${4:-.}  # Default to current directory if no folder is specified
user_offset=${5:-}     # Optional user-specified offset

# Automatically generate raw log file and filtered CSV file names
raw_log_file="${output_folder}/${base_file_name}_raw.log"
filtered_csv_file="${output_folder}/${base_file_name}_filter.csv"

# Check if 'jq' is installed
jq_installed=false
if command -v jq &> /dev/null; then
    jq_installed=true
    echo "'jq' is available, will use it for parsing."
else
    echo "'jq' is not available, will use grep/awk/sed for parsing."
fi

# Extract file size from the FIO job descriptor
file_size=$(grep -Eo 'size=[0-9]+[KMG]' "$fio_job_file" | awk -F= '{print $2}')
if [ -z "$file_size" ]; then
    echo "Error: Could not extract file size from the FIO job descriptor."
    exit 1
fi

# Convert file size to bytes for offset calculation
file_size_bytes=$(numfmt --from=iec "${file_size}")
if [ $? -ne 0 ] || [ -z "$file_size_bytes" ]; then
    echo "Error: Invalid file size in FIO job descriptor."
    exit 1
fi

# Extract the operation type (read or write) from the FIO job descriptor
operation=$(grep -Eo 'rw=[a-z]+' "$fio_job_file" | awk -F= '{print $2}')
if [ -z "$operation" ]; then
    echo "Error: Could not extract operation type from the FIO job descriptor."
    exit 1
fi

# Check if the output folder exists and create it if it doesn't
if [ ! -d "$output_folder" ]; then
    echo "Output folder '$output_folder' does not exist. Creating it..."
    mkdir -p "$output_folder"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create output folder '$output_folder'."
        exit 1
    fi
fi


# Check if log files already exist and ask for confirmation to overwrite
if [ -e "$raw_log_file" ] || [ -e "$filtered_csv_file" ]; then
    echo "Log files $raw_log_file and/or $filtered_csv_file already exist."
    read -p "Do you want to overwrite the existing log files? (y/n): " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
        echo "Exiting without overwriting log files."
        exit 0
    fi
fi

# Clear the log files if they already exist and user confirmed to overwrite
: > "$raw_log_file"
: > "$filtered_csv_file"

# Write the header to the CSV file
echo "Iteration,Operation,IOPS,Bandwidth (KB/s)" >> $filtered_csv_file


# Set initial offset to 0
current_offset=0

# Loop control - Run 'fio' for the specified number of iterations
for (( i=1; i<=iterations; i++ ))
do
    echo "Running iteration $i..., offset $current_offset"

    # Build the fio command, applying the offset calculated so far
    fio_command="fio --output-format=json $fio_job_file --offset=${current_offset}"

    # Run fio and capture its output in JSON format
    #fio_output=$(fio --output-format=json $fio_job_file)
    fio_output=$($fio_command 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Error: fio command failed. Skipping iteration $i."
        continue
    fi

    # Log raw data to the raw log file
    echo "Iteration $i Raw Data:" >> $raw_log_file
    echo "$fio_output" >> $raw_log_file
    echo "" >> $raw_log_file

    # Extract IOPS and bandwidth based on the operation type
    if $jq_installed; then
        if [ "$operation" == "write" ]; then
            iops=$(echo "$fio_output" | jq -r '.jobs[].write.iops // 0')
            bw=$(echo "$fio_output" | jq -r '.jobs[].write.bw // 0')
        elif [ "$operation" == "read" ]; then
            iops=$(echo "$fio_output" | jq -r '.jobs[].read.iops // 0')
            bw=$(echo "$fio_output" | jq -r '.jobs[].read.bw // 0')
        else
            echo "Error: Unknown operation type. Skipping iteration $i."
            continue
        fi
    else
        if [ "$operation" == "write" ]; then
            iops=$(echo "$fio_output" | grep '"iops"' | sed -n '2p' | awk -F ': ' '{print $2}' | tr -d ',' || echo 0)
            bw=$(echo "$fio_output" | grep '"bw"' | sed -n '2p' | awk -F ': ' '{print $2}' | tr -d ',' || echo 0)
        elif [ "$operation" == "read" ]; then
            iops=$(echo "$fio_output" | grep '"iops"' | sed -n '1p' | awk -F ': ' '{print $2}' | tr -d ',' || echo 0)
            bw=$(echo "$fio_output" | grep '"bw"' | sed -n '1p' | awk -F ': ' '{print $2}' | tr -d ',' || echo 0)
        else
            echo "Error: Unknown operation type. Skipping iteration $i."
            continue
        fi
    fi
    # Debugging: Print extracted values
    echo "Debug: iops = '$iops', bw = '$bw'"

    # Check if variables are empty or non-numeric
    #if [[ -z "$iops" || -z "$bw" ]]; then #|| ! "$iops" =~ ^[0-9]+$ || ! "$bw" =~ ^[0-9]+$ ]]; then
    if [[ -z "$iops" || -z "$bw" || ! "$iops" =~ ^[0-9]+(\.[0-9]+)?$ || ! "$bw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Error: Failed to extract valid IOPS or bandwidth. Skipping iteration $i."
        continue
    fi


    # Write the filtered results to the CSV file
    echo "$i,$operation,$iops,$bw" >> $filtered_csv_file

    # Print the extracted IOPS and bandwidth to the console
    echo "Iteration $i Results:"
    echo "Operation: $operation"
    echo "IOPS: $iops"
    echo "Bandwidth (KB/s): $bw"
    echo ""


    # Increment the offset for the next iteration
    current_offset=$((current_offset + file_size_bytes))

    # Optional: sleep between iterations if desired (adjust duration as needed)
    sleep 1
done

echo "All iterations completed. Raw data logged to $raw_log_file, filtered results logged to $filtered_csv_file."

