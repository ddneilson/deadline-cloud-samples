#!/bin/bash

echo "Script location: $0 Output location: $1"
export OUTPUT_DIR=$1
mkdir $OUTPUT_DIR
echo "Script location: $0" >> $OUTPUT_DIR/output.txt
