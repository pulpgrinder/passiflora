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

# Generated JS config file (consumed by the web app)
CONFIG_JS = src/www/generated/config.js

# C source layout
SRCDIR = src/C
GENDIR = src/C/generated

all: $(BINARY) bundle

$(GENDIR)/zipdata.c: $(CONTENT)
	@mkdir -p $(GENDIR)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c

$(GENDIR)/menu.c: $(MENU_TEMPLATE) nixscripts/mkmenu.sh
	@mkdir -p $(GENDIR)
	sh nixscripts/mkmenu.sh $(MENU_TEMPLATE) $(PROGNAME) $(GENDIR)/menu.c

$(GENDIR)/win_menu.c: src/Windows/menus/menu.txt nixscripts/mkmenu.sh
	@mkdir -p $(GENDIR)
	sh nixscripts/mkmenu.sh src/Windows/menus/menu.txt $(PROGNAME) $(GENDIR)/win_menu.c

$(BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.c $(SRCDIR)/UI.c $(GENDIR)/menu.c
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh $(MENU_TEMPLATE) $(PROGNAME) $(OS_NAME) $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c
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

$(IOS_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.c $(SRCDIR)/UI.c $(GENDIR)/menu.c
ifeq ($(UNAME_S),Darwin)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/iOS/menus/menu.txt $(PROGNAME) iOS $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c
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

# ── iOS Simulator (build + install + launch) ───────────────────────
iossim: $(SIMOS_BINARY) iossim-bundle iossim-run

$(SIMOS_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.c $(SRCDIR)/UI.c $(GENDIR)/menu.c
ifeq ($(UNAME_S),Darwin)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/iOS/menus/menu.txt $(PROGNAME) iOS $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c
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

windows: $(GENDIR)/win_menu.c $(WV2_LOADER_H) $(WIN_BINARY)

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

$(WIN_BINARY): $(SRCDIR)/passiflora.c $(SRCDIR)/zipzip.c $(SRCDIR)/UI.c $(GENDIR)/win_menu.c $(WV2_LOADER_H)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/Windows/menus/menu.txt $(PROGNAME) Windows $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c
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

linux: $(GENDIR)/menu.c
ifeq ($(UNAME_S),Linux)
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/Linux/menus/menu.txt $(PROGNAME) Linux $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c
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
android: $(GENDIR)/menu.c
	@mkdir -p $(dir $(CONFIG_JS))
	sh nixscripts/mkmenu_json.sh src/android/menus/menu.txt $(PROGNAME) Android $(CONFIG_JS)
	sh nixscripts/mkzipfile.sh $(CONTENT) $(GENDIR)/zipdata.c
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

.PHONY: all clean icons bundle sign-macos ios ios-bundle sign-ios iossim iossim-bundle sign-iossim iossim-run windows linux android sign-android
