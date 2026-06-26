#!/bin/bash

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <path_to_dylib> <path_to_app_binary>"
    exit 1
fi

DYLIB_PATH="$1"
APP_BINARY="$2"

if [ ! -f "$DYLIB_PATH" ]; then
    echo "Error: Dylib not found at $DYLIB_PATH"
    exit 1
fi

if [ ! -f "$APP_BINARY" ]; then
    echo "Error: App binary not found at $APP_BINARY"
    exit 1
fi

echo "Starting injection..."
echo "Dylib: $DYLIB_PATH"
echo "Target: $APP_BINARY"

BINARY_DIR=$(dirname "$APP_BINARY")
FRAMEWORKS_DIR="$BINARY_DIR/Frameworks"

mkdir -p "$FRAMEWORKS_DIR"

cp "$DYLIB_PATH" "$FRAMEWORKS_DIR/"

if command -v insert_dylib >/dev/null 2>&1; then
    INSERT_DYLIB="insert_dylib"
elif [ -f "/usr/local/bin/insert_dylib" ]; then
    INSERT_DYLIB="/usr/local/bin/insert_dylib"
elif [ -f "./insert_dylib" ]; then
    INSERT_DYLIB="./insert_dylib"
else
    echo "Error: insert_dylib not found. Please install it first."
    echo "Install with: brew install insert_dylib"
    exit 1
fi

"$INSERT_DYLIB" --weak @rpath/AutoClicker.dylib "$APP_BINARY" "$APP_BINARY.new"

if [ -f "$APP_BINARY.new" ]; then
    mv "$APP_BINARY" "$APP_BINARY.backup"
    mv "$APP_BINARY.new" "$APP_BINARY"
    chmod +x "$APP_BINARY"
    echo "Injection completed successfully!"
    echo "Backup saved at: $APP_BINARY.backup"
else
    echo "Error: Injection failed"
    exit 1
fi

echo "Done!"