TARGET = arm64-apple-ios14.0
SDK_PATH = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC = xcrun -sdk iphoneos clang
CFLAGS = -arch arm64 -target $(TARGET) -isysroot $(SDK_PATH) -fobjc-arc -ObjC
LDFLAGS = -dynamiclib -framework Foundation -framework UIKit -framework IOKit -framework CoreGraphics
INSTALL_NAME = @rpath/AutoClicker.dylib

SRC = src/AutoClicker.m
OUTPUT = AutoClicker.dylib

all: $(OUTPUT)

$(OUTPUT): $(SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(OUTPUT) $(SRC) -install_name $(INSTALL_NAME)

clean:
	rm -f $(OUTPUT)

install: $(OUTPUT)
	mkdir -p /tmp/auto_clicker
	cp $(OUTPUT) /tmp/auto_clicker/

.PHONY: all clean install