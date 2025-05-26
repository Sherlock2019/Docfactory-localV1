#!/bin/bash

# Define the output file name
OUTPUT_FILE="allcode.txt"

# Define the project root (assuming script is run from the project's base directory)
PROJECT_ROOT=$(pwd)

# List of files to concatenate, relative to PROJECT_ROOT
FILES_TO_CAT=(
    "utils/document_filler.py"
    "utils/extract_placeholders.py"
    "app.py"
    "static/style.css"
    "templates/index.html"
    "templates/download_complete.html"
    "requirements.txt"
)

echo "--- Concatenating Specific Project Files to $OUTPUT_FILE ---"

# Clear the output file if it already exists, or create it
> "$OUTPUT_FILE"

# Iterate through the list of files and append their content
for file in "${FILES_TO_CAT[@]}"; do
    FULL_PATH="$PROJECT_ROOT/$file"
    if [ -f "$FULL_PATH" ]; then
        echo "Appending: $file"
        echo "========================================" >> "$OUTPUT_FILE"
        echo "File: $file" >> "$OUTPUT_FILE"
        echo "========================================" >> "$OUTPUT_FILE"
        cat "$FULL_PATH" >> "$OUTPUT_FILE"
        echo -e "\n\n" >> "$OUTPUT_FILE" # Add extra newlines for separation
    else
        echo "WARNING: File not found, skipping: $file"
    fi
done

echo "All specified code concatenated into $OUTPUT_FILE"
echo "--- Script Finished ---"


