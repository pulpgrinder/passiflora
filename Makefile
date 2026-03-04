PROGNAME = HeckinChonker
CC      ?= cc
CFLAGS  ?= -Wall -Wextra -O2
LDFLAGS ?= -lpthread
CONTENT ?= src/www

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  OS_NAME        = macOS
  UI_CFLAGS      = -x objective-c -fobjc-arc
  UI_LDFLAGS     = -framework Cocoa -framework WebKit
  MENU_TEMPLATE  = src/macOS/menus/menu.txt
  BUNDLE_ID     ?= com.example.$(PROGNAME)
  VERSION       ?= 1.0.0
  ICNS           = src/icons/builticons/macos/AppIcon.icns
  APP_BUNDLE     = $(BINDIR)/$(PROGNAME).app

  # iOS cross-compilation settings
  IOS_SDK       := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
  IOS_CC         = xcrun -sdk iphoneos clang
  IOS_ARCH      ?= arm64
  IOS_MIN       ?= 15.0
  IOS_CFLAGS     = -x objective-c -fobjc-arc -arch $(IOS_ARCH) \
                   -isysroot $(IOS_SDK) -miphoneos-version-min=$(IOS_MIN) \
                   -Wall -Wextra -O2
  IOS_LDFLAGS    = -arch $(IOS_ARCH) -isysroot $(IOS_SDK) \
                   -miphoneos-version-min=$(IOS_MIN) \
                   -framework UIKit -framework WebKit -framework CoreGraphics -lpthread
  IOS_BINDIR     = bin/iOS
  IOS_BINARY     = $(IOS_BINDIR)/$(PROGNAME)
  IOS_APP_BUNDLE = $(IOS_BINDIR)/$(PROGNAME).app

  # iOS Simulator settings
  SIMOS_SDK     := $(shell xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
  SIMOS_CC       = xcrun -sdk iphonesimulator clang
  SIMOS_ARCH    ?= arm64
  SIMOS_CFLAGS   = -x objective-c -fobjc-arc -arch $(SIMOS_ARCH) \
                   -isysroot $(SIMOS_SDK) -mios-simulator-version-min=$(IOS_MIN) \
                   -Wall -Wextra -O2
  SIMOS_LDFLAGS  = -arch $(SIMOS_ARCH) -isysroot $(SIMOS_SDK) \
                   -mios-simulator-version-min=$(IOS_MIN) \
                   -framework UIKit -framework WebKit -framework CoreGraphics -lpthread
  SIMOS_BINDIR   = bin/iOS-sim
  SIMOS_BINARY   = $(SIMOS_BINDIR)/$(PROGNAME)
  SIMOS_APP_BUNDLE = $(SIMOS_BINDIR)/$(PROGNAME).app
else ifeq ($(UNAME_S),Linux)
  OS_NAME        = Linux
  WEBKIT_PKG    := $(shell pkg-config --exists webkit2gtk-4.1 2>/dev/null && echo webkit2gtk-4.1 || echo webkit2gtk-4.0)
  UI_CFLAGS      = $(shell pkg-config --cflags gtk+-3.0 $(WEBKIT_PKG) 2>/dev/null)
  UI_LDFLAGS     = $(shell pkg-config --libs gtk+-3.0 $(WEBKIT_PKG) 2>/dev/null)
  MENU_TEMPLATE  = src/Linux/menus/menu.txt
else
  OS_NAME        = $(UNAME_S)
endif

# Windows cross-compilation (mingw-w64)
WIN_CC        ?= x86_64-w64-mingw32-gcc
WIN_WINDRES   ?= x86_64-w64-mingw32-windres
WIN_CFLAGS     = -Wall -Wextra -O2
WIN_LDFLAGS    = -lws2_32 -lshell32 -lgdi32 -lole32 -luuid -mwindows -static -lpthread
WIN_BINDIR     = bin/Windows
WIN_BINARY     = $(WIN_BINDIR)/$(PROGNAME).exe

BINDIR  = bin/$(OS_NAME)
BINARY  = $(BINDIR)/$(PROGNAME)

SYSTEMID_JS = src/www/systemid.js

all: $(BINARY) bundle

zipdata.c: $(CONTENT)
	sh mkzipfile.sh $(CONTENT) zipdata.c

menu.c: $(MENU_TEMPLATE) mkmenu.sh
	sh mkmenu.sh $(MENU_TEMPLATE) $(PROGNAME) menu.c

win_menu.c: src/Windows/menus/menu.txt mkmenu.sh
	sh mkmenu.sh src/Windows/menus/menu.txt $(PROGNAME) win_menu.c

# JSON menus for iOS and Android (consumed by the web app)
IOS_MENU_JSON     = src/www/generated/iOS/menus.json
ANDROID_MENU_JSON = src/www/generated/android/menus.json

$(IOS_MENU_JSON): src/iOS/menus/menu.txt mkmenu_json.sh
	sh mkmenu_json.sh src/iOS/menus/menu.txt $(PROGNAME) $(IOS_MENU_JSON)

$(ANDROID_MENU_JSON): src/android/menus/menu.txt mkmenu_json.sh
	sh mkmenu_json.sh src/android/menus/menu.txt $(PROGNAME) $(ANDROID_MENU_JSON)

$(BINARY): passiflora.c zipzip.c UI.c menu.c
	@printf '// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = "%s";\n' "$(OS_NAME)" > $(SYSTEMID_JS)
	sh mkzipfile.sh $(CONTENT) zipdata.c
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $(UI_CFLAGS) -o $@ passiflora.c UI.c $(LDFLAGS) $(UI_LDFLAGS)

icons:
	bash src/icons/buildiconset.sh

bundle: $(BINARY)
ifeq ($(UNAME_S),Darwin)
	sh mkbundle.sh $(PROGNAME) $(BINARY) $(ICNS) $(BUNDLE_ID) $(VERSION)
endif

# ── iOS (cross-compile from macOS) ──────────────────────────────────
ios: $(IOS_BINARY) ios-bundle

$(IOS_BINARY): passiflora.c zipzip.c UI.c menu.c $(IOS_MENU_JSON)
ifeq ($(UNAME_S),Darwin)
	@printf '// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = "iOS";\n' > $(SYSTEMID_JS)
	sh mkzipfile.sh $(CONTENT) zipdata.c
	mkdir -p $(IOS_BINDIR)
	$(IOS_CC) $(IOS_CFLAGS) -o $@ passiflora.c UI.c $(IOS_LDFLAGS)
else
	@echo "iOS target requires macOS with Xcode." >&2; exit 1
endif

ios-bundle: $(IOS_BINARY)
ifeq ($(UNAME_S),Darwin)
	sh mkiosbundle.sh $(PROGNAME) $(IOS_BINARY) src/icons/builticons/ios/AppIcon-1024.png $(BUNDLE_ID) $(VERSION)
endif

# ── iOS Simulator (build + install + launch) ───────────────────────
iossim: $(SIMOS_BINARY) iossim-bundle iossim-run

$(SIMOS_BINARY): passiflora.c zipzip.c UI.c menu.c $(IOS_MENU_JSON)
ifeq ($(UNAME_S),Darwin)
	@printf '// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = "iOS";\n' > $(SYSTEMID_JS)
	sh mkzipfile.sh $(CONTENT) zipdata.c
	mkdir -p $(SIMOS_BINDIR)
	$(SIMOS_CC) $(SIMOS_CFLAGS) -o $@ passiflora.c UI.c $(SIMOS_LDFLAGS)
else
	@echo "iOS Simulator target requires macOS with Xcode." >&2; exit 1
endif

iossim-bundle: $(SIMOS_BINARY)
ifeq ($(UNAME_S),Darwin)
	sh mkiosbundle.sh $(PROGNAME) $(SIMOS_BINARY) src/icons/builticons/ios/AppIcon-1024.png $(BUNDLE_ID) $(VERSION) $(SIMOS_BINDIR)
endif

iossim-run: iossim-bundle
ifeq ($(UNAME_S),Darwin)
	@# Boot the most recent available iPhone if nothing is booted
	@if ! xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then \
		UDID=$$(xcrun simctl list devices available -j \
			| python3 -c "import sys,json; ds=[d for devs in json.loads(sys.stdin.read())['devices'].values() for d in devs if d['isAvailable'] and 'iPhone' in d['name']]; print(ds[-1]['udid'] if ds else '')" 2>/dev/null); \
		if [ -n "$$UDID" ]; then \
			echo "Booting simulator $$UDID..."; \
			xcrun simctl boot "$$UDID"; \
			sleep 2; \
		else \
			echo "No available iPhone simulator found." >&2; exit 1; \
		fi; \
	fi
	open -a Simulator 2>/dev/null || true
	xcrun simctl install booted $(SIMOS_APP_BUNDLE)
	xcrun simctl launch booted $(BUNDLE_ID)
	@echo "Launched $(PROGNAME) in iOS Simulator."
endif

# ── Windows (cross-compile via mingw-w64) ──────────────────────
WV2_NUGET_VER  = 1.0.2903.40
WV2_NUGET_URL  = https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$(WV2_NUGET_VER)
WV2_LOADER_H   = wv2loader.h

windows: win_menu.c $(WV2_LOADER_H) $(WIN_BINARY)

# Download WebView2Loader.dll and convert to an embedded C header
$(WV2_LOADER_H):
	@echo "Downloading WebView2Loader.dll …"
	@mkdir -p $(WIN_BINDIR)
	@curl -sL $(WV2_NUGET_URL) -o $(WIN_BINDIR)/webview2.zip
	@unzip -oj $(WIN_BINDIR)/webview2.zip \
	    "runtimes/win-x64/native/WebView2Loader.dll" \
	    -d $(WIN_BINDIR) >/dev/null 2>&1
	@rm -f $(WIN_BINDIR)/webview2.zip
	@echo "/* Generated — WebView2Loader.dll embedded as byte array */" > $@
	@echo "static const unsigned char wv2loader_dll[] = {" >> $@
	@xxd -i < $(WIN_BINDIR)/WebView2Loader.dll \
	    | sed '$$s/,$$//' >> $@
	@echo "};" >> $@
	@echo "static const unsigned int wv2loader_dll_len = \\" >> $@
	@wc -c < $(WIN_BINDIR)/WebView2Loader.dll | tr -d ' ' >> $@
	@echo ";" >> $@
	@rm -f $(WIN_BINDIR)/WebView2Loader.dll
	@echo "$(WV2_LOADER_H) generated (embedded WebView2Loader.dll)"

$(WIN_BINARY): passiflora.c zipzip.c UI.c win_menu.c $(WV2_LOADER_H)
	@printf '// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = "Windows";\n' > $(SYSTEMID_JS)
	sh mkzipfile.sh $(CONTENT) zipdata.c
	mkdir -p $(WIN_BINDIR)
	@if [ -f src/icons/builticons/windows/app.ico ] && \
	    command -v $(WIN_WINDRES) >/dev/null 2>&1; then \
		echo '1 ICON "src/icons/builticons/windows/app.ico"' \
		    > $(WIN_BINDIR)/app.rc; \
		$(WIN_WINDRES) $(WIN_BINDIR)/app.rc -o $(WIN_BINDIR)/app_res.o; \
		$(WIN_CC) $(WIN_CFLAGS) -o $@ passiflora.c UI.c \
		    $(WIN_BINDIR)/app_res.o $(WIN_LDFLAGS); \
	else \
		$(WIN_CC) $(WIN_CFLAGS) -o $@ passiflora.c UI.c $(WIN_LDFLAGS); \
	fi

# ── Linux (native build on Linux) ──────────────────────────────────
linux: menu.c
ifeq ($(UNAME_S),Linux)
	@printf '// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = "Linux";\n' > $(SYSTEMID_JS)
	sh mkzipfile.sh $(CONTENT) zipdata.c
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $(UI_CFLAGS) -o $(BINARY) passiflora.c UI.c $(LDFLAGS) $(UI_LDFLAGS)
else
	@echo "Linux target requires building on a Linux system." >&2
	@echo "  Install: sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev" >&2; exit 1
endif

# ── Android (Gradle + NDK) ─────────────────────────────────
android: menu.c $(ANDROID_MENU_JSON)
	@printf '// Auto-generated file — DO NOT EDIT. This file is overwritten on every build.\nPASSIFLORA_OS_NAME = "Android";\n' > $(SYSTEMID_JS)
	sh mkzipfile.sh $(CONTENT) zipdata.c
	sh mkandroid.sh $(PROGNAME) $(BUNDLE_ID) $(VERSION)

clean:
	rm -f $(BINARY) zipdata.c menu.c
	rm -rf $(APP_BUNDLE)
	rm -f $(IOS_BINARY)
	rm -rf $(IOS_APP_BUNDLE)
	rm -f $(SIMOS_BINARY)
	rm -rf $(SIMOS_APP_BUNDLE)
	rm -f $(WIN_BINARY)
	rm -f $(WIN_BINDIR)/app.rc $(WIN_BINDIR)/app_res.o
	rm -f wv2loader.h win_menu.c
	rm -f $(SYSTEMID_JS)
	rm -rf src/www/generated
	rm -rf bin/Android/gradle-build bin/Android/gradle-cache src/android/.gradle src/android/app/.cxx
	rm -f bin/Android/*.apk
	-rmdir -p $(BINDIR) 2>/dev/null || true
	-rmdir -p $(IOS_BINDIR) 2>/dev/null || true
	-rmdir -p $(SIMOS_BINDIR) 2>/dev/null || true
	-rmdir -p $(WIN_BINDIR) 2>/dev/null || true
	-rmdir -p bin/Android 2>/dev/null || true

.PHONY: all clean icons bundle ios ios-bundle iossim iossim-bundle iossim-run windows linux android
