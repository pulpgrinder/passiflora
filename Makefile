PROGNAME = HeckinChonker
CC      ?= cc
CFLAGS  ?= -Wall -Wextra -O2
LDFLAGS ?= -lpthread
CONTENT ?= src/www

# ── Permissions (read from src/permissions) ─────────────────────────
PERM_LOCATION   := $(shell awk '/^location /   {print $$2}' src/permissions 2>/dev/null)
PERM_CAMERA     := $(shell awk '/^camera /     {print $$2}' src/permissions 2>/dev/null)
PERM_MICROPHONE := $(shell awk '/^microphone / {print $$2}' src/permissions 2>/dev/null)

PERM_DEFS :=
ifeq ($(PERM_LOCATION),1)
  PERM_DEFS += -DPERM_LOCATION
endif
ifeq ($(PERM_CAMERA),1)
  PERM_DEFS += -DPERM_CAMERA
endif
ifeq ($(PERM_MICROPHONE),1)
  PERM_DEFS += -DPERM_MICROPHONE
endif

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  OS_NAME        = macOS
  UI_CFLAGS      = -x objective-c -fobjc-arc $(PERM_DEFS)
  UI_LDFLAGS     = -framework Cocoa -framework WebKit
  ifeq ($(PERM_LOCATION),1)
    UI_LDFLAGS  += -framework CoreLocation
  endif
  ifneq (,$(filter 1,$(PERM_CAMERA) $(PERM_MICROPHONE)))
    UI_LDFLAGS  += -framework AVFoundation -framework CoreMedia
  endif
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
                   $(PERM_DEFS) -Wall -Wextra -O2
  IOS_LDFLAGS    = -arch $(IOS_ARCH) -isysroot $(IOS_SDK) \
                   -miphoneos-version-min=$(IOS_MIN) \
                   -framework UIKit -framework WebKit -framework CoreGraphics -lpthread
  ifeq ($(PERM_LOCATION),1)
    IOS_LDFLAGS += -framework CoreLocation
  endif
  ifneq (,$(filter 1,$(PERM_CAMERA) $(PERM_MICROPHONE)))
    IOS_LDFLAGS += -framework AVFoundation -framework CoreMedia
  endif
  IOS_BINDIR     = bin/iOS
  IOS_BINARY     = $(IOS_BINDIR)/$(PROGNAME)
  IOS_APP_BUNDLE = $(IOS_BINDIR)/$(PROGNAME).app

  # iOS Simulator settings
  SIMOS_SDK     := $(shell xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
  SIMOS_CC       = xcrun -sdk iphonesimulator clang
  SIMOS_ARCH    ?= arm64
  SIMOS_CFLAGS   = -x objective-c -fobjc-arc -arch $(SIMOS_ARCH) \
                   -isysroot $(SIMOS_SDK) -mios-simulator-version-min=$(IOS_MIN) \
                   $(PERM_DEFS) -Wall -Wextra -O2
  SIMOS_LDFLAGS  = -arch $(SIMOS_ARCH) -isysroot $(SIMOS_SDK) \
                   -mios-simulator-version-min=$(IOS_MIN) \
                   -framework UIKit -framework WebKit -framework CoreGraphics -lpthread
  ifeq ($(PERM_LOCATION),1)
    SIMOS_LDFLAGS += -framework CoreLocation
  endif
  ifneq (,$(filter 1,$(PERM_CAMERA) $(PERM_MICROPHONE)))
    SIMOS_LDFLAGS += -framework AVFoundation -framework CoreMedia
  endif
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

# Generated JS config file (consumed by the web app)
CONFIG_JS = src/www/generated/config.js

# C source layout
SRCDIR = src/C
GENDIR = src/C/generated

all: $(BINARY) bundle

# ── macOS (alias for consistency with other platform targets) ────────
makemacos:
ifeq ($(UNAME_S),Darwin)
	$(MAKE) all
else
	@echo "makemacos target requires macOS." >&2
endif

$(GENDIR)/zipdata.h: $(CONTENT)
	@mkdir -p $(GENDIR)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h

$(GENDIR)/menu.h: $(MENU_TEMPLATE) nixscripts/mkmenu.sh
	@mkdir -p $(GENDIR)
	sh nixscripts/mkmenu.sh $(MENU_TEMPLATE) $(PROGNAME) $(GENDIR)/menu.h

$(GENDIR)/win_menu.h: src/Windows/menus/menu.txt nixscripts/mkmenu.sh
	@mkdir -p $(GENDIR)
	sh nixscripts/mkmenu.sh src/Windows/menus/menu.txt $(PROGNAME) $(GENDIR)/win_menu.h

$(BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/menu.h
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh $(MENU_TEMPLATE) $(PROGNAME) $(OS_NAME) $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
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
	sh nixscripts/mkbundle.sh $(PROGNAME) $(BINARY) $(ICNS) $(BUNDLE_ID) $(VERSION)
endif

sign: bundle
sign-macos: bundle
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/signapp.sh macos $(APP_BUNDLE) $(BUNDLE_ID)
else
	@echo "sign-macos target requires macOS." >&2; exit 1
endif

# ── iOS (cross-compile from macOS) ──────────────────────────────────
ios: $(IOS_BINARY) ios-bundle

$(IOS_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/menu.h
ifeq ($(UNAME_S),Darwin)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/iOS/menus/menu.txt $(PROGNAME) iOS $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	mkdir -p $(IOS_BINDIR)
	$(IOS_CC) $(IOS_CFLAGS) -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(IOS_LDFLAGS)
else
	@echo "iOS target requires macOS with Xcode." >&2; exit 1
endif

ios-bundle: $(IOS_BINARY)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkiosbundle.sh $(PROGNAME) $(IOS_BINARY) src/icons/builticons/ios/AppIcon-1024.png $(BUNDLE_ID) $(VERSION)
endif

sign-ios: ios-bundle
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/signapp.sh ios $(IOS_APP_BUNDLE) $(BUNDLE_ID)
else
	@echo "sign-ios target requires macOS." >&2; exit 1
endif

# ── iOS IPA (signed, release-ready) ────────────────────────────────
IOS_IPA = $(IOS_BINDIR)/$(PROGNAME).ipa

iosipa: ios-bundle
ifeq ($(UNAME_S),Darwin)
	@PROV="$(IOS_PROVISIONING_PROFILE)"; \
	if [ -z "$$PROV" ]; then \
		printf 'Provisioning profile (.mobileprovision): '; read PROV; \
	fi; \
	if [ -z "$$PROV" ] || [ ! -f "$$PROV" ]; then \
		echo "iosipa: provisioning profile not found: $$PROV" >&2; \
		echo "  Set IOS_PROVISIONING_PROFILE or provide the path when prompted." >&2; \
		exit 1; \
	fi; \
	echo "iosipa: embedding provisioning profile..."; \
	cp "$$PROV" $(IOS_APP_BUNDLE)/embedded.mobileprovision; \
	\
	echo "iosipa: extracting entitlements from profile..."; \
	ENT_FILE=$$(mktemp /tmp/iosipa-ent-XXXXXX); \
	security cms -D -i "$$PROV" > "$$ENT_FILE.full"; \
	if ! /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$$ENT_FILE.full" > "$$ENT_FILE"; then \
		echo "iosipa: failed to extract entitlements from provisioning profile." >&2; \
		cat "$$ENT_FILE.full" >&2; \
		rm -f "$$ENT_FILE" "$$ENT_FILE.full"; \
		exit 1; \
	fi; \
	rm -f "$$ENT_FILE.full"; \
	echo "iosipa: entitlements:"; \
	cat "$$ENT_FILE"; \
	\
	echo ""; \
	echo "=== Code Signing: $(IOS_APP_BUNDLE) ==="; \
	echo ""; \
	echo "Platform: iOS (device — IPA packaging)"; \
	echo ""; \
	echo "Signing options:"; \
	echo "  • Apple Distribution / iPhone Distribution — For App Store or enterprise distribution."; \
	echo "  • Apple Development / iPhone Developer — For ad-hoc/device testing."; \
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
		echo "iosipa: no selection made, aborting." >&2; \
		rm -f "$$ENT_FILE"; \
		exit 1; \
	fi; \
	LINE=$$(echo "$$IDENTITIES" | sed -n "$${CHOICE}p"); \
	if [ -z "$$LINE" ]; then \
		echo "iosipa: invalid selection." >&2; \
		rm -f "$$ENT_FILE"; \
		exit 1; \
	fi; \
	SIGN_ID=$$(echo "$$LINE" | sed 's/^[0-9]*) *\([A-F0-9]*\).*/\1/'); \
	SIGN_DESC=$$(echo "$$LINE" | sed 's/.*"\(.*\)".*/\1/'); \
	echo ""; \
	echo "Signing with: $$SIGN_DESC"; \
	\
	codesign --force \
		--sign "$$SIGN_ID" \
		--entitlements "$$ENT_FILE" \
		--generate-entitlement-der \
		$(IOS_APP_BUNDLE); \
	rm -f "$$ENT_FILE"; \
	\
	echo ""; \
	echo "iosipa: $(IOS_APP_BUNDLE) signed."; \
	codesign -dvv $(IOS_APP_BUNDLE) 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature)'; \
	\
	echo ""; \
	echo "iosipa: packaging $(IOS_IPA)..."; \
	rm -rf $(IOS_BINDIR)/_ipa_staging; \
	mkdir -p $(IOS_BINDIR)/_ipa_staging/Payload; \
	cp -R $(IOS_APP_BUNDLE) $(IOS_BINDIR)/_ipa_staging/Payload/; \
	cd $(IOS_BINDIR)/_ipa_staging && zip -qr "$(CURDIR)/$(IOS_IPA)" Payload; \
	rm -rf $(IOS_BINDIR)/_ipa_staging; \
	echo "iosipa: $(IOS_IPA) created."
else
	@echo "iosipa target requires macOS." >&2; exit 1
endif

# ── iOS Simulator (build + install + launch) ───────────────────────
iossim: $(SIMOS_BINARY) iossim-bundle iossim-run

$(SIMOS_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/menu.h
ifeq ($(UNAME_S),Darwin)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/iOS/menus/menu.txt $(PROGNAME) iOS $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	mkdir -p $(SIMOS_BINDIR)
	$(SIMOS_CC) $(SIMOS_CFLAGS) -o $@ $(SRCDIR)/passiflora.c $(SRCDIR)/UI.c $(SIMOS_LDFLAGS)
else
	@echo "iOS Simulator target requires macOS with Xcode." >&2; exit 1
endif

iossim-bundle: $(SIMOS_BINARY)
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/mkiosbundle.sh $(PROGNAME) $(SIMOS_BINARY) src/icons/builticons/ios/AppIcon-1024.png $(BUNDLE_ID) $(VERSION) $(SIMOS_BINDIR)
endif

sign-iossim: iossim-bundle
ifeq ($(UNAME_S),Darwin)
	sh nixscripts/signapp.sh iossim $(SIMOS_APP_BUNDLE) $(BUNDLE_ID)
else
	@echo "sign-iossim target requires macOS." >&2; exit 1
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

$(WIN_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.h $(SRCDIR)/UI.c $(GENDIR)/win_menu.h $(WV2_LOADER_H)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/Windows/menus/menu.txt $(PROGNAME) Windows $(CONFIG_JS)
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

# ── Linux (native build on Linux) ──────────────────────────────────
LINUX_ICON_PNG      = src/icons/builticons/linux/icon-256.png
LINUX_ICON_FALLBACK = src/icons/builticons/macos/AppIcon.iconset/icon_256x256.png
LINUX_ICON_H        = src/C/generated/linux_icon.h

linux: $(GENDIR)/menu.h
ifeq ($(UNAME_S),Linux)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/Linux/menus/menu.txt $(PROGNAME) Linux $(CONFIG_JS)
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
else
	@echo "Linux target requires building on a Linux system." >&2
	@echo "  Install: sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev" >&2; exit 1
endif

# ── Android (Gradle + NDK) ─────────────────────────────────
android: $(GENDIR)/menu.h
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/android/menus/menu.txt $(PROGNAME) Android $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.h
	sh nixscripts/mkandroid.sh $(PROGNAME) $(BUNDLE_ID) $(VERSION)

# ── Android signing (local keystore) ───────────────────────
ANDROID_APK = bin/Android/$(PROGNAME).apk

sign-android: android
	@if [ ! -f "$(ANDROID_APK)" ]; then \
		echo "sign-android: APK not found: $(ANDROID_APK)" >&2; \
		echo "  Run 'make android' first." >&2; \
		exit 1; \
	fi
	@printf 'Keystore file: '; read KS_FILE; \
	if [ ! -f "$$KS_FILE" ]; then \
		echo "sign-android: keystore not found: $$KS_FILE" >&2; \
		exit 1; \
	fi; \
	printf 'Keystore password: '; \
	stty -echo 2>/dev/null; read KS_PASS; stty echo 2>/dev/null; echo; \
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

clean:
	rm -f $(BINARY)
	rm -rf $(GENDIR)
	rm -rf $(APP_BUNDLE)
	rm -f $(IOS_BINARY)
	rm -rf $(IOS_APP_BUNDLE)
	rm -f bin/iOS/$(PROGNAME).ipa
	rm -rf bin/iOS/_ipa_staging
	rm -f $(SIMOS_BINARY)
	rm -rf $(SIMOS_APP_BUNDLE)
	rm -f $(WIN_BINARY)
	rm -f $(WIN_BINDIR)/app.rc $(WIN_BINDIR)/app_res.o
	rm -f wv2loader.h
	rm -rf src/www/generated
	rm -rf bin/Android/gradle-build bin/Android/gradle-cache src/android/.gradle src/android/app/.cxx
	rm -f bin/Android/*.apk
ifeq ($(UNAME_S),Linux)
	rm -f $(HOME)/.local/share/icons/hicolor/256x256/apps/$(PROGNAME).png
	rm -f $(HOME)/.local/share/applications/$(PROGNAME).desktop
	-gtk-update-icon-cache -f -t $(HOME)/.local/share/icons/hicolor 2>/dev/null || true
endif

.PHONY: all clean icons bundle sign-macos ios ios-bundle sign-ios iosipa iossim iossim-bundle sign-iossim iossim-run windows linux android sign-android
