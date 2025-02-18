#!/usr/bin/env bash
set -euo pipefail

REINDEXING_DIR=
S3_CHANNEL=
CONDA_CHANNEL_NAME=

# Parse the CLI arguments
while [ $# -gt 0 ]; do
    case "${1}" in
    --reindexing-dir) REINDEXING_DIR="$2" ; shift 2 ;;
    --s3-conda-channel) S3_CHANNEL="$2" ; shift 2 ;;
    --conda-channel-name) CONDA_CHANNEL_NAME="$2" ; shift 2 ;;
    *) echo "Unexpected option: $1" ; exit 1 ;;
  esac
done

if [ -z "$REINDEXING_DIR" ]; then
    echo "ERROR: Option --reindexing-dir is required."
    exit 1
fi
if [ -z "$S3_CHANNEL" ]; then
    echo "ERROR: Option --s3-conda-channel is required."
    exit 1
fi
if [ -z "$CONDA_CHANNEL_NAME" ]; then
    echo "ERROR: Option --conda-channel-name is required."
    exit 1
fi

# Trim the trailing '/' from the S3 channel URL if necessary
S3_CHANNEL=${S3_CHANNEL%/}

if [[ "$S3_CHANNEL" =~ ^s3://([^/]+)/(.*)/?$ ]]; then
    S3_CHANNEL_BUCKET=${BASH_REMATCH[1]}
    S3_CHANNEL_PREFIX=${BASH_REMATCH[2]}
else
    echo "ERROR: The value for --s3-conda-channel does not match s3://<bucket-name>/prefix."
    exit 1
fi

CHANNEL_INDEXING_DIR="$REINDEXING_DIR/index-dir"
CHANNEL_MOUNTPOINT="$REINDEXING_DIR/mountpoint"
mkdir -p $CHANNEL_INDEXING_DIR
mkdir -p $CHANNEL_MOUNTPOINT

echo "Mounting the S3 channel..."
mount-s3 --prefix $S3_CHANNEL_PREFIX/ \
    --read-only \
    $S3_CHANNEL_BUCKET $CHANNEL_MOUNTPOINT

# Clean up on exit
function unmount_channel {
    fusermount -u $CHANNEL_MOUNTPOINT
}
trap unmount_channel EXIT

echo "Wiring up an indexing view of the channel packages..."

CHANNEL_DIRS=$(shopt -s nullglob; echo $CHANNEL_MOUNTPOINT/linux-* $CHANNEL_MOUNTPOINT/win-* $CHANNEL_MOUNTPOINT/osx-* $CHANNEL_MOUNTPOINT/noarch)
for CHANNEL_DIR in $CHANNEL_DIRS; do
    if [ -d $CHANNEL_DIR ]; then
        echo "Found $(basename $CHANNEL_DIR) in the channel"
        mkdir -p $CHANNEL_INDEXING_DIR/$(basename $CHANNEL_DIR)
        for PACKAGE in $(cd $CHANNEL_DIR; \
                        shopt -s nullglob; echo *.conda); do
            ln -r -s $CHANNEL_DIR/$PACKAGE \
                $CHANNEL_INDEXING_DIR/$(basename $CHANNEL_DIR)/$PACKAGE
        done
        if [ -f "$CHANNEL_DIR/.cache/cache.db" ]; then
            mkdir -p "$CHANNEL_INDEXING_DIR/$(basename $CHANNEL_DIR)/.cache"
            cp "$CHANNEL_DIR/.cache/cache.db" "$CHANNEL_INDEXING_DIR/$(basename $CHANNEL_DIR)/.cache/"
        fi
    fi
done

echo "Indexing the channel view in the indexing view..."
python -m conda_index \
    --zst \
    --channel-name "$CONDA_CHANNEL_NAME" \
    $CHANNEL_INDEXING_DIR
echo ""

echo "Contents of the channel:"
find $CHANNEL_INDEXING_DIR
echo ""

echo "Synchronizing the updated index to the S3 bucket..."
aws s3 sync $CHANNEL_INDEXING_DIR \
    $S3_CHANNEL \
    --exclude "*" \
    --include "*/repodata.json" \
    --include "*/repodata.json.zst" \
    --include "*/index.html" \
    --include "*/.cache/cache.db"
echo ""

echo "Reindexing completed."
