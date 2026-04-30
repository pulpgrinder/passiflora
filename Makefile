PROGNAME := $(shell awk '/^PROGNAME / {print $$2}' src/config 2>/dev/null)
DISPLAYNAME := $(shell awk '/^DISPLAYNAME / {sub(/^DISPLAYNAME /, ""); print}' src/config 2>/dev/null)
ifeq ($(DISPLAYNAME),)
  DISPLAYNAME := $(PROGNAME)
endif
CC      ?= cc
CFLAGS  ?= -Wall -Wextra -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2
LDFLAGS ?= -lpthread
CONTENT ?= src/www

# All web content files (excluding build-generated ones) — used as
# dependencies so that changes to HTML, CSS, or JS trigger a rebuild.
WEB_SOURCES := $(shell find $(CONTENT) -type f -not -path '*/generated/*' 2>/dev/null)

# Framework sources (passiflora library) — also trigger rebuilds.
FRAMEWORK_SOURCES := $(shell find src/passiflora -type f 2>/dev/null)

# ── Permissions (read from src/config) ──────────────────────────────
PERM_LOCATION   := $(shell awk '/^uselocation /          {print $$2}' src/config 2>/dev/null)
PERM_CAMERA     := $(shell awk '/^usecamera /            {print $$2}' src/config 2>/dev/null)
PERM_MICROPHONE := $(shell awk '/^usemicrophone /        {print $$2}' src/config 2>/dev/null)
PERM_REMOTEDEBUGGING := $(shell awk '/^allowremotedebugging / {print $$2}' src/config 2>/dev/null)
THEME := $(shell awk '/^theme / {sub(/^theme /, ""); print}' src/config 2>/dev/null)
ifeq ($(THEME),)
  THEME := Default
endif

# ── Port (read from src/config; generate if missing) ───────────────
PORT := $(shell awk '/^port / {print $$2}' src/config 2>/dev/null)
ifeq ($(PORT),)
  PORT := $(shell awk 'BEGIN{srand(); print int(40000+rand()*22001)}')
  $(shell echo 'port $(PORT)' >> src/config)
endif

PERM_DEFS := -DPROGNAME_STR=\"$(PROGNAME)\" -DDEFAULT_PORT=$(PORT)
ifeq ($(PERM_LOCATION),true)
  PERM_DEFS += -DPERM_LOCATION
endif
ifeq ($(PERM_CAMERA),true)
  PERM_DEFS += -DPERM_CAMERA
endif
ifeq ($(PERM_MICROPHONE),true)
  PERM_DEFS += -DPERM_MICROPHONE
endif
ifeq ($(PERM_REMOTEDEBUGGING),true)
  PERM_DEFS += -DPERM_REMOTEDEBUGGING
endif

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  OS_NAME        = macOS
  UI_CFLAGS      = -x objective-c -fobjc-arc $(PERM_DEFS)
  UI_LDFLAGS     = -framework Cocoa -framework WebKit
  ifeq ($(PERM_LOCATION),true)
    UI_LDFLAGS  += -framework CoreLocation
  endif
  MENU_TEMPLATE  = src/macOS/menus/menu.txt
  BUNDLE_ID     := $(shell awk '/^BUNDLE_ID / {print $$2}' src/config 2>/dev/null)
  VERSION       ?= 1.0.0
  ICNS           = src/icons/builticons/macos/AppIcon.icns
  APP_BUNDLE     = $(BINDIR)/$(DISPLAYNAME).app

  # iOS cross-compilation settings
  IOS_SDK       := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
  IOS_CC         = xcrun -sdk iphoneos clang
  IOS_ARCH      ?= arm64
  IOS_MIN       ?= 15.0
  IOS_CFLAGS     = -x objective-c -fobjc-arc -arch $(IOS_ARCH) \
                   -isysroot $(IOS_SDK) -miphoneos-version-min=$(IOS_MIN) \
                   $(PERM_DEFS) -Wall -Wextra -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2
  IOS_LDFLAGS    = -arch $(IOS_ARCH) -isysroot $(IOS_SDK) \
                   -miphoneos-version-min=$(IOS_MIN) \
                   -framework UIKit -framework WebKit -framework CoreGraphics -lpthread
  ifeq ($(PERM_LOCATION),true)
    IOS_LDFLAGS += -framework CoreLocation
  endif
  ifeq ($(PERM_REMOTEDEBUGGING),true)
    IOS_LDFLAGS += -framework Network
  endif
  IOS_BINDIR     = bin/iOS
  IOS_BINARY     = $(IOS_BINDIR)/$(PROGNAME)
  IOS_APP_BUNDLE = $(IOS_BINDIR)/$(DISPLAYNAME).app

  # iOS Simulator settings
  SIMOS_SDK     := $(shell xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
  SIMOS_CC       = xcrun -sdk iphonesimulator clang
  SIMOS_ARCH    ?= arm64
  SIMOS_CFLAGS   = -x objective-c -fobjc-arc -arch $(SIMOS_ARCH) \
                   -isysroot $(SIMOS_SDK) -mios-simulator-version-min=$(IOS_MIN) \
                   $(PERM_DEFS) -Wall -Wextra -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2
  SIMOS_LDFLAGS  = -arch $(SIMOS_ARCH) -isysroot $(SIMOS_SDK) \
                   -mios-simulator-version-min=$(IOS_MIN) \
                   -framework UIKit -framework WebKit -framework CoreGraphics -lpthread
  ifeq ($(PERM_LOCATION),true)
    SIMOS_LDFLAGS += -framework CoreLocation
  endif
  ifeq ($(PERM_REMOTEDEBUGGING),true)
    SIMOS_LDFLAGS += -framework Network
  endif
  SIMOS_BINDIR   = bin/iOS-sim
  SIMOS_BINARY   = $(SIMOS_BINDIR)/$(PROGNAME)
  SIMOS_APP_BUNDLE = $(SIMOS_BINDIR)/$(DISPLAYNAME).app
else ifeq ($(UNAME_S),Linux)
  OS_NAME        = Linux
  WEBKIT_PKG    := $(shell pkg-config --exists webkit2gtk-4.1 2>/dev/null && echo webkit2gtk-4.1 || echo webkit2gtk-4.0)
  UI_CFLAGS      = $(shell pkg-config --cflags gtk+-3.0 $(WEBKIT_PKG) 2>/dev/null) $(PERM_DEFS)
  UI_LDFLAGS     = $(shell pkg-config --libs gtk+-3.0 $(WEBKIT_PKG) 2>/dev/null)
  # GStreamer for native recording (when camera or microphone enabled)
  ifneq (,$(filter true,$(PERM_CAMERA) $(PERM_MICROPHONE)))
    UI_CFLAGS   += $(shell pkg-config --cflags gstreamer-1.0 2>/dev/null)
    UI_LDFLAGS  += $(shell pkg-config --libs gstreamer-1.0 2>/dev/null)
  endif
  MENU_TEMPLATE  = src/Linux/menus/menu.txt
else
  OS_NAME        = $(UNAME_S)
endif

# Windows cross-compilation (mingw-w64)
WIN_CC        ?= x86_64-w64-mingw32-gcc
WIN_WINDRES   ?= x86_64-w64-mingw32-windres
WIN_CFLAGS     = -Wall -Wextra -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -D__USE_MINGW_ANSI_STDIO=1 $(PERM_DEFS)
WIN_LDFLAGS    = -lws2_32 -lshell32 -lgdi32 -lole32 -luuid -lshlwapi -mwindows -static -lpthread
WIN_BINDIR     = bin/Windows
WIN_BINARY     = $(WIN_BINDIR)/$(PROGNAME).exe

BINDIR  = bin/$(OS_NAME)
BINARY  = $(BINDIR)/$(PROGNAME)

# C source layout
SRCDIR = src/C
GENDIR = src/C/generated

# Default target: build for the current platform only
.DEFAULT_GOAL := default
default:
ifeq ($(UNAME_S),Darwin)
	$(MAKE) macos
else ifeq ($(UNAME_S),Linux)
	$(MAKE) linux
else
	$(MAKE) $(BINARY) bundle
endif

all:
ifeq ($(UNAME_S),Darwin)
	$(MAKE) clean
	$(MAKE) macos
	$(MAKE) $(IOS_BINARY)
	$(MAKE) windows
	$(MAKE) android
	$(MAKE) www
else ifeq ($(UNAME_S),Linux)
	$(MAKE) clean
	$(MAKE) linux
	$(MAKE) windows
	$(MAKE) android
	$(MAKE) www
else
	$(MAKE) $(BINARY) bundle
endif

sign-all:
ifeq ($(UNAME_S),Darwin)
	$(MAKE) clean
	$(MAKE) sign-macos
	$(MAKE) sign-ios
	$(MAKE) sign-windows
	$(MAKE) sign-android
	$(MAKE) googleplay-android
	$(MAKE) www
else
	@echo "sign-all target requires macOS." >&2; exit 1
endif

# ── macOS (alias for consistency with other platform targets) ────────
macos:
ifeq ($(UNAME_S),Darwin)
	$(MAKE) $(BINARY) bundle
else
	@echo "macos target requires macOS." >&2
endif

$(GENDIR)/zipdata.h: $(WEB_SOURCES) $(FRAMEWORK_SOURCES)
	@mkdir -p $(GENDIR)
	sh nixscripts/mkgenerated.sh "$(MENU_TEMPLATE)" "$(PROGNAME)" "$(OS_NAME)" "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h

$(GENDIR)/menu.h: $(MENU_TEMPLATE) nixscripts/mkmenu.sh
	@mkdir -p $(GENDIR)
	sh nixscripts/mkmenu.sh "$(MENU_TEMPLATE)" "$(PROGNAME)" "$(GENDIR)/menu.h"

$(GENDIR)/win_menu.h: src/Windows/menus/menu.txt nixscripts/mkmenu.sh
	@mkdir -p $(GENDIR)
	sh nixscripts/mkmenu.sh src/Windows/menus/menu.txt "$(PROGNAME)" "$(GENDIR)/win_menu.h"

$(BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/menu.h $(WEB_SOURCES) $(FRAMEWORK_SOURCES)
	sh nixscripts/mkgenerated.sh "$(MENU_TEMPLATE)" "$(PROGNAME)" "$(OS_NAME)" "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh "$(CONTENT)" "$(GENDIR)/zipdata.h"
ifeq ($(UNAME_S),Linux)
	@# Generate linux_icon.h with embedded icon (or stub if no icon available)
	@mkdir -p $(GENDIR)
	@_ICON="$(LINUX_ICON_PNG)"; \
	if [ ! -f "$$_ICON" ]; then _ICON="$(LINUX_ICON_FALLBACK)"; fi; \
	if [ -f "$$_ICON" ]; then \
		echo "/* Generated — app icon embedded as byte array */" > $(LINUX_ICON_H); \
		echo "static const unsigned char linux_icon_png[] = {" >> $(LINUX_ICON_H); \
		xxd -i < "$$_ICON" >> $(LINUX_ICON_H); \
		echo "};" >> $(LINUX_ICON_H); \
		echo "static const unsigned int linux_icon_png_len = sizeof(linux_icon_png);" >> $(LINUX_ICON_H); \
	else \
		echo "/* No icon available */" > $(LINUX_ICON_H); \
		echo "static const unsigned char linux_icon_png[] = {0};" >> $(LINUX_ICON_H); \
		echo "static const unsigned int linux_icon_png_len = 0;" >> $(LINUX_ICON_H); \
	fi
endif
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $(UI_CFLAGS) -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(LDFLAGS) $(UI_LDFLAGS)

icons:
	bash src/icons/buildiconset.sh

bundle: $(BINARY)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkbundle.sh "$(PROGNAME)" "$(BINARY)" "$(ICNS)" "$(BUNDLE_ID)" "$(VERSION)" "$(DISPLAYNAME)"
endif

sign: bundle
sign-macos: bundle
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/signapp.sh macos "$(APP_BUNDLE)" $(BUNDLE_ID)
else
	@echo "sign-macos target requires macOS." >&2; exit 1
endif

# ── iOS (cross-compile from macOS) ──────────────────────────────────
$(IOS_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/menu.h $(WEB_SOURCES) $(FRAMEWORK_SOURCES)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkgenerated.sh src/iOS/menus/menu.txt "$(PROGNAME)" iOS "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh "$(CONTENT)" "$(GENDIR)/zipdata.h"
	mkdir -p $(IOS_BINDIR)
	$(IOS_CC) $(IOS_CFLAGS) -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(IOS_LDFLAGS)
else
	@echo "iOS target requires macOS with Xcode." >&2; exit 1
endif

# ── iOS IPA (signed, release-ready) ────────────────────────────────
IOS_IPA = $(IOS_BINDIR)/$(PROGNAME).ipa

sign-ios: $(IOS_BINARY)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkiosbundle.sh "$(PROGNAME)" "$(IOS_BINARY)" src/icons/builticons/ios/AppIcon-1024.png "$(BUNDLE_ID)" "$(VERSION)" "" "$(DISPLAYNAME)"
	@PROV="$(IOS_PROVISIONING_PROFILE)"; \
	if [ -z "$$PROV" ]; then \
		PROFILE_DIR="$$HOME/passiflora-keys"; \
		PROFILES=$$(find "$$PROFILE_DIR" -maxdepth 1 -type f -name '*.mobileprovision' -print 2>/dev/null | sort); \
		if [ -n "$$PROFILES" ]; then \
			echo ""; \
			echo "Available provisioning profiles in $$PROFILE_DIR:"; \
			echo ""; \
			printf '%s\n' "$$PROFILES" | awk -F/ '{printf "  %d) %s\n", NR, $$NF}'; \
			PROFILE_COUNT=$$(printf '%s\n' "$$PROFILES" | wc -l | tr -d ' '); \
			echo ""; \
			printf "Choose provisioning profile [1-$$PROFILE_COUNT], or press Enter to type a path: "; read PROV_CHOICE; \
			if [ -n "$$PROV_CHOICE" ]; then \
				case "$$PROV_CHOICE" in \
					*[!0-9]*) PROV="$$PROV_CHOICE" ;; \
					*) PROV=$$(printf '%s\n' "$$PROFILES" | sed -n "$${PROV_CHOICE}p") ;; \
				esac; \
				if [ -z "$$PROV" ]; then \
					echo "sign-ios: invalid provisioning profile selection." >&2; \
					exit 1; \
				fi; \
			fi; \
		fi; \
	fi; \
	if [ -z "$$PROV" ]; then \
		printf 'Provisioning profile (.mobileprovision): '; read PROV; \
	fi; \
	if [ -z "$$PROV" ] || [ ! -f "$$PROV" ]; then \
		echo "sign-ios: provisioning profile not found: $$PROV" >&2; \
		echo "  Set IOS_PROVISIONING_PROFILE, choose one from ~/passiflora-keys, or provide the path when prompted." >&2; \
		exit 1; \
	fi; \
	echo "sign-ios: embedding provisioning profile..."; \
	cp "$$PROV" "$(IOS_APP_BUNDLE)/embedded.mobileprovision"; \
	\
	echo "sign-ios: extracting entitlements from profile..."; \
	ENT_FILE=$$(mktemp /tmp/sign-ios-ent-XXXXXX); \
	TMPDIR_IPA=""; \
	trap 'rm -f "$$ENT_FILE" "$$ENT_FILE.full"; [ -n "$$TMPDIR_IPA" ] && rm -rf "$$TMPDIR_IPA"' EXIT; \
	security cms -D -i "$$PROV" > "$$ENT_FILE.full"; \
	if ! /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$$ENT_FILE.full" > "$$ENT_FILE"; then \
		echo "sign-ios: failed to extract entitlements from provisioning profile." >&2; \
		cat "$$ENT_FILE.full" >&2; \
		exit 1; \
	fi; \
	echo "sign-ios: entitlements:"; \
	cat "$$ENT_FILE"; \
	\
	PROFILE_APPID=$$(/usr/libexec/PlistBuddy -c "Print :application-identifier" "$$ENT_FILE" 2>/dev/null \
		| sed 's/^[A-Z0-9]*\.//'); \
	PLIST_BUNDLEID=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$(IOS_APP_BUNDLE)/Info.plist" 2>/dev/null); \
	if [ -n "$$PROFILE_APPID" ] && [ -n "$$PLIST_BUNDLEID" ] && [ "$$PROFILE_APPID" != "$$PLIST_BUNDLEID" ]; then \
		echo "" >&2; \
		echo "sign-ios: ERROR — bundle ID mismatch:" >&2; \
		echo "  Info.plist:           $$PLIST_BUNDLEID" >&2; \
		echo "  Provisioning profile: $$PROFILE_APPID" >&2; \
		echo "" >&2; \
		echo "  Set BUNDLE_ID to match your profile:" >&2; \
		echo "    make sign-ios BUNDLE_ID=$$PROFILE_APPID" >&2; \
		exit 1; \
	fi; \
	\
	echo ""; \
	echo "=== Code Signing: $(IOS_APP_BUNDLE) ==="; \
	echo ""; \
	echo "Platform: iOS (device — IPA packaging)"; \
	echo ""; \
	echo "Signing options:"; \
	echo "  • Apple Development / iPhone Developer — For installing on local devices (ad-hoc testing)."; \
	echo "  • Apple Distribution / iPhone Distribution — For App Store or enterprise distribution ONLY."; \
	echo ""; \
	echo "For sideloading to a local device, choose a DEVELOPMENT certificate."; \
	echo ""; \
	IDENTITIES=$$(security find-identity -v -p codesigning 2>/dev/null \
		| grep -E '^\s+[0-9]+\)' | sed 's/^[[:space:]]*//'); \
	N=0; \
	if [ -n "$$IDENTITIES" ]; then \
		echo "Available signing identities:"; \
		echo ""; \
		echo "$$IDENTITIES" | while IFS= read -r line; do \
			DESC=$$(echo "$$line" | sed 's/.*"\(.*\)".*/\1/'); \
			NUM=$$(echo "$$line" | sed 's/^\([0-9]*\)).*/\1/'); \
			echo "  $$NUM) $$DESC"; \
		done; \
		N=$$(echo "$$IDENTITIES" | wc -l | tr -d ' '); \
	fi; \
	echo ""; \
	printf "Choose identity [1-$$N]: "; read CHOICE; \
	if [ -z "$$CHOICE" ]; then \
		echo "sign-ios: no selection made, aborting." >&2; \
		exit 1; \
	fi; \
	LINE=$$(echo "$$IDENTITIES" | sed -n "$${CHOICE}p"); \
	if [ -z "$$LINE" ]; then \
		echo "sign-ios: invalid selection." >&2; \
		exit 1; \
	fi; \
	SIGN_ID=$$(echo "$$LINE" | sed 's/^[0-9]*) *\([A-F0-9]*\).*/\1/'); \
	SIGN_DESC=$$(echo "$$LINE" | sed 's/.*"\(.*\)".*/\1/'); \
	echo ""; \
	echo "Signing with: $$SIGN_DESC"; \
	\
	TMPDIR_IPA=$$(mktemp -d /tmp/sign-ios-ipa-XXXXXX); \
	echo "sign-ios: copying bundle to $$TMPDIR_IPA (avoids iCloud xattr interference)..."; \
	ditto "$(IOS_APP_BUNDLE)" "$$TMPDIR_IPA/$(DISPLAYNAME).app"; \
	xattr -cr "$$TMPDIR_IPA/$(DISPLAYNAME).app"; \
	codesign --force \
		--sign "$$SIGN_ID" \
		--entitlements "$$ENT_FILE" \
		--generate-entitlement-der \
		"$$TMPDIR_IPA/$(DISPLAYNAME).app"; \
	\
	echo ""; \
	echo "sign-ios: bundle signed."; \
	codesign -dvv "$$TMPDIR_IPA/$(DISPLAYNAME).app" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature)'; \
	\
	echo ""; \
	echo "sign-ios: packaging $(IOS_IPA)..."; \
	mkdir -p "$$TMPDIR_IPA/Payload"; \
	mv "$$TMPDIR_IPA/$(DISPLAYNAME).app" "$$TMPDIR_IPA/Payload/"; \
	ditto -c -k --keepParent \
		"$$TMPDIR_IPA/Payload" "$(CURDIR)/$(IOS_IPA)"; \
	echo "sign-ios: $(IOS_IPA) created."
else
	@echo "sign-ios target requires macOS." >&2; exit 1
endif

# ── iOS Simulator (build + install + launch) ───────────────────────
$(SIMOS_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/menu.h $(WEB_SOURCES) $(FRAMEWORK_SOURCES)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkgenerated.sh src/iOS/menus/menu.txt "$(PROGNAME)" iOS "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh "$(CONTENT)" "$(GENDIR)/zipdata.h"
	mkdir -p $(SIMOS_BINDIR)
	$(SIMOS_CC) $(SIMOS_CFLAGS) -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(SIMOS_LDFLAGS)
else
	@echo "iOS Simulator target requires macOS with Xcode." >&2; exit 1
endif

sim-ios: $(SIMOS_BINARY)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkiosbundle.sh "$(PROGNAME)" "$(SIMOS_BINARY)" src/icons/builticons/ios/AppIcon-1024.png "$(BUNDLE_ID)" "$(VERSION)" "$(SIMOS_BINDIR)" "$(DISPLAYNAME)"
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
	xcrun simctl install booted "$(SIMOS_APP_BUNDLE)"
	xcrun simctl launch booted $(BUNDLE_ID)
	@echo "Launched $(PROGNAME) in iOS Simulator."
else
	@echo "iOS Simulator target requires macOS with Xcode." >&2; exit 1
endif

# ── Windows (cross-compile via mingw-w64) ──────────────────────
WV2_NUGET_VER  = 1.0.2903.40
WV2_NUGET_URL  = https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$(WV2_NUGET_VER)
WV2_LOADER_H   = wv2loader.h

windows: $(GENDIR)/win_menu.h $(WV2_LOADER_H) $(WIN_BINARY)

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

$(WIN_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/win_menu.h $(WV2_LOADER_H) $(WEB_SOURCES) $(FRAMEWORK_SOURCES)
	sh nixscripts/mkgenerated.sh src/Windows/menus/menu.txt "$(PROGNAME)" Windows "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	mkdir -p $(WIN_BINDIR)
	@if [ -f src/icons/builticons/windows/app.ico ] && \
	    command -v $(WIN_WINDRES) >/dev/null 2>&1; then \
		echo '1 ICON "src/icons/builticons/windows/app.ico"' \
		    > $(WIN_BINDIR)/app.rc; \
		$(WIN_WINDRES) $(WIN_BINDIR)/app.rc -o $(WIN_BINDIR)/app_res.o; \
		$(WIN_CC) $(WIN_CFLAGS) -I. -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c \
		    $(WIN_BINDIR)/app_res.o $(WIN_LDFLAGS); \
	else \
		$(WIN_CC) $(WIN_CFLAGS) -I. -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(WIN_LDFLAGS); \
	fi
	@mv "$@" "$(WIN_BINDIR)/$(DISPLAYNAME).exe"

# ── Windows signing (Azure Trusted Signing via jsign) ──────────────
WIN_EXE = $(WIN_BINDIR)/$(DISPLAYNAME).exe

sign-windows: windows
	@if [ ! -f "$(WIN_EXE)" ]; then \
		echo "sign-windows: exe not found: $(WIN_EXE)" >&2; \
		echo "  Run 'make windows' first." >&2; \
		exit 1; \
	fi
	@if ! command -v jsign >/dev/null 2>&1; then \
		echo "sign-windows: jsign not found on PATH." >&2; \
		echo "  Install with: brew install jsign  (macOS/Linux)" >&2; \
		exit 1; \
	fi
	@if [ -z "$$AZURE_SIGNING_ENDPOINT" ] || [ -z "$$AZURE_SIGNING_ACCOUNT" ] || [ -z "$$AZURE_SIGNING_PROFILE" ]; then \
		echo "sign-windows: missing one or more required environment variables:" >&2; \
		echo "  AZURE_SIGNING_ENDPOINT  (e.g. https://eus.codesigning.azure.net)" >&2; \
		echo "  AZURE_SIGNING_ACCOUNT   (your Artifact Signing account name)" >&2; \
		echo "  AZURE_SIGNING_PROFILE   (your certificate profile name)" >&2; \
		exit 1; \
	fi
	@echo "sign-windows: obtaining Azure access token..."
	$(eval AZURE_TOKEN := $(shell az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv))
	@if [ -z "$(AZURE_TOKEN)" ]; then \
		echo "sign-windows: failed to obtain Azure access token." >&2; \
		echo "  Make sure the Azure CLI is installed and you are logged in (az login)." >&2; \
		exit 1; \
	fi
	@echo "sign-windows: signing $(WIN_EXE)..."
	@jsign --storetype TRUSTEDSIGNING \
		--keystore "$$AZURE_SIGNING_ENDPOINT" \
		--storepass "$(AZURE_TOKEN)" \
		--alias "$$AZURE_SIGNING_ACCOUNT/$$AZURE_SIGNING_PROFILE" \
		--tsaurl http://timestamp.acs.microsoft.com \
		--tsmode RFC3161 \
		"$(WIN_EXE)"
	@echo "sign-windows: $(WIN_EXE) signed successfully."

# ── Linux (native build on Linux) ──────────────────────────────────
LINUX_ICON_PNG      = src/icons/builticons/linux/icon-256.png
LINUX_ICON_FALLBACK = src/icons/builticons/macos/AppIcon.iconset/icon_256x256.png
LINUX_ICON_H        = src/C/generated/linux_icon.h

linux: $(GENDIR)/menu.h
ifeq ($(UNAME_S),Linux)
	sh nixscripts/mkgenerated.sh src/Linux/menus/menu.txt "$(PROGNAME)" Linux "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	@mkdir -p $(GENDIR)
	@_ICON="$(LINUX_ICON_PNG)"; \
	if [ ! -f "$$_ICON" ]; then _ICON="$(LINUX_ICON_FALLBACK)"; fi; \
	if [ -f "$$_ICON" ]; then \
		echo "/* Generated — app icon embedded as byte array */" > $(LINUX_ICON_H); \
		echo "static const unsigned char linux_icon_png[] = {" >> $(LINUX_ICON_H); \
		xxd -i < "$$_ICON" >> $(LINUX_ICON_H); \
		echo "};" >> $(LINUX_ICON_H); \
		echo "static const unsigned int linux_icon_png_len = sizeof(linux_icon_png);" >> $(LINUX_ICON_H); \
	else \
		echo "/* No icon available */" > $(LINUX_ICON_H); \
		echo "static const unsigned char linux_icon_png[] = {0};" >> $(LINUX_ICON_H); \
		echo "static const unsigned int linux_icon_png_len = 0;" >> $(LINUX_ICON_H); \
	fi
	mkdir -p $(BINDIR)
	$(CC) $(CFLAGS) $(UI_CFLAGS) -o $(BINARY) $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(LDFLAGS) $(UI_LDFLAGS)
	@mv "$(BINARY)" "$(BINDIR)/$(DISPLAYNAME)"
else
	@echo "Linux target requires building on a Linux system." >&2
	@echo "  Install: sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev" >&2; exit 1
endif

# ── Android (Gradle + NDK) ─────────────────────────────────
android: $(GENDIR)/menu.h
	sh nixscripts/mkgenerated.sh src/android/menus/menu.txt "$(PROGNAME)" Android "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	sh nixscripts/mkandroid.sh $(PROGNAME) $(BUNDLE_ID) $(VERSION)

# ── Android App Bundle (Google Play) ───────────────────────
googleplay-android: $(GENDIR)/menu.h
	sh nixscripts/mkgenerated.sh src/android/menus/menu.txt "$(PROGNAME)" Android "$(THEME)" src/config
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	BUILD_TYPE=release BUILD_FORMAT=aab sh nixscripts/mkandroid.sh $(PROGNAME) $(BUNDLE_ID) $(VERSION)

# ── Android signing (local keystore) ───────────────────────
ANDROID_APK = bin/Android/$(PROGNAME).apk

sign-android: android
	@if [ ! -f "$(ANDROID_APK)" ]; then \
		echo "sign-android: APK not found: $(ANDROID_APK)" >&2; \
		echo "  Run 'make android' first." >&2; \
		exit 1; \
	fi
	@KS_FILE=~/passiflora-keys/android-keystore.jks; \
	if [ ! -f "$$KS_FILE" ]; then \
		printf 'Keystore file: '; read KS_FILE; \
		if [ ! -f "$$KS_FILE" ]; then \
			echo "sign-android: keystore not found: $$KS_FILE" >&2; \
			exit 1; \
		fi; \
	else \
		echo "sign-android: using keystore $$KS_FILE"; \
	fi; \
	printf 'Keystore password: '; \
	stty -echo 2>/dev/null; read KS_PASS; stty echo 2>/dev/null; echo; \
	if [ -z "$$ANDROID_HOME" ]; then \
		for _d in "$$HOME/Library/Android/sdk" "$$HOME/Android/Sdk" "/usr/local/lib/android/sdk"; do \
			if [ -d "$$_d" ]; then ANDROID_HOME="$$_d"; break; fi; \
		done; \
		if [ -z "$$ANDROID_HOME" ] && [ -f src/android/local.properties ]; then \
			ANDROID_HOME=$$(sed -n 's/^sdk\.dir=//p' src/android/local.properties); \
		fi; \
	fi; \
	APKSIGNER=""; \
	if [ -n "$$ANDROID_HOME" ]; then \
		APKSIGNER=$$(find "$$ANDROID_HOME/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1); \
	fi; \
	if [ -z "$$APKSIGNER" ]; then \
		if command -v apksigner >/dev/null 2>&1; then \
			APKSIGNER=apksigner; \
		else \
			echo "sign-android: apksigner not found. Set ANDROID_HOME or add build-tools to PATH." >&2; \
			exit 1; \
		fi; \
	fi; \
	echo "sign-android: zipaligning APK..."; \
	ZIPALIGN=""; \
	if [ -n "$$ANDROID_HOME" ]; then \
		ZIPALIGN=$$(find "$$ANDROID_HOME/build-tools" -name zipalign -type f 2>/dev/null | sort -V | tail -1); \
	fi; \
	if [ -z "$$ZIPALIGN" ] && command -v zipalign >/dev/null 2>&1; then \
		ZIPALIGN=zipalign; \
	fi; \
	if [ -n "$$ZIPALIGN" ]; then \
		$$ZIPALIGN -f 4 "$(ANDROID_APK)" "$(ANDROID_APK).aligned"; \
		mv "$(ANDROID_APK).aligned" "$(ANDROID_APK)"; \
	else \
		echo "sign-android: warning: zipalign not found, skipping alignment." >&2; \
	fi; \
	echo "sign-android: signing $(ANDROID_APK)..."; \
	printf '%s' "$$KS_PASS" | $$APKSIGNER sign --ks "$$KS_FILE" --ks-pass stdin "$(ANDROID_APK)"; \
	echo "sign-android: verifying signature..."; \
	$$APKSIGNER verify "$(ANDROID_APK)"; \
	echo "sign-android: $(ANDROID_APK) signed successfully."

# ── WWW (plain browser — no native build) ──────────────────────────
WWW_BINDIR = bin/WWW

www:
	sh nixscripts/mkgenerated.sh src/WWW/menus/menu.txt "$(PROGNAME)" WWW "$(THEME)" src/config
	@rm -rf $(WWW_BINDIR)
	@mkdir -p $(WWW_BINDIR)
	cp -R $(CONTENT)/* $(WWW_BINDIR)/
	@echo ""
	@echo "=== WWW target ready (bin/WWW/) ==="
	@echo "Run the development server with:"
	@echo "  python3 webserver.py"
	@echo "Then open http://localhost:8000 in your browser."
	@echo ""

# ── New project (disconnect from upstream and push to a new GitHub repo) ──
newproject:
	@if ! command -v gh >/dev/null 2>&1; then \
		echo "newproject: GitHub CLI (gh) is required but not found." >&2; \
		echo "  Install from: https://cli.github.com/" >&2; \
		exit 1; \
	fi
	@if ! command -v git >/dev/null 2>&1; then \
		echo "newproject: git is required but not found." >&2; \
		exit 1; \
	fi
	@printf 'New project name: '; read NEWNAME; \
	if [ -z "$$NEWNAME" ]; then \
		echo "newproject: no name provided." >&2; \
		exit 1; \
	fi; \
	echo "Creating new GitHub repository: $$NEWNAME"; \
	rm -rf .git; \
	git init; \
	git add .; \
	git commit -m "Initial commit"; \
	gh repo create "$$NEWNAME" --private --source=. --remote=origin --push; \
	echo ""; \
	echo "New project '$$NEWNAME' created and pushed to GitHub."

clean:
	rm -f $(BINARY)
	rm -f "$(BINDIR)/$(DISPLAYNAME)"
	rm -rf $(GENDIR)
	rm -rf "$(APP_BUNDLE)"
	rm -f $(IOS_BINARY)
	rm -rf "$(IOS_APP_BUNDLE)"
	rm -f bin/iOS/$(PROGNAME).ipa
	rm -rf bin/iOS/_ipa_staging
	rm -f $(SIMOS_BINARY)
	rm -rf "$(SIMOS_APP_BUNDLE)"
	rm -f $(WIN_BINARY)
	rm -f "$(WIN_EXE)"
	rm -f $(WIN_BINDIR)/app.rc $(WIN_BINDIR)/app_res.o
	rm -f wv2loader.h
	rm -rf src/www/generated
	rm -rf $(WWW_BINDIR)
	rm -rf bin/Android/gradle-build bin/Android/gradle-cache src/android/.gradle src/android/app/.cxx
	rm -f bin/Android/*.apk bin/Android/*.aab
ifeq ($(UNAME_S),Linux)
	rm -f $(HOME)/.local/share/icons/hicolor/256x256/apps/$(PROGNAME).png
	rm -f $(HOME)/.local/share/applications/$(PROGNAME).desktop
	-gtk-update-icon-cache -f -t $(HOME)/.local/share/icons/hicolor 2>/dev/null || true
endif

.PHONY: default all sign-all clean icons bundle macos sign-macos sign-ios sim-ios windows sign-windows linux android sign-android googleplay-android www newproject
