/*
 * UI.c — Platform-specific native window with embedded web view.
 *
 * Provides ui_open(port) which opens a native window containing a
 * full-window web view pointed at http://localhost:<port>/.
 * This function runs the platform event loop and does not return
 * until the window is closed (at which point the process exits).
 *
 * Compile notes:
 *   macOS:   compile as Objective-C (-x objective-c),
 *            link with -framework Cocoa -framework WebKit
 *   iOS:     compile as Objective-C (-x objective-c),
 *            link with -framework UIKit -framework WebKit
 *   Windows: link with -lgdi32 -lshell32 -lole32 -mwindows
 *   Linux:   link with $(pkg-config --libs gtk+-3.0 webkit2gtk-4.1)
 */

#include <stdio.h>
#include <stdlib.h>

/* ================================================================== */
/*  macOS / iOS                                                        */
/* ================================================================== */
#if defined(__APPLE__) && defined(__MACH__)

#include <TargetConditionals.h>

#if TARGET_OS_IPHONE
/* ------------------------------------------------------------------ */
/*  iOS — UIKit + WKWebView                                            */
/* ------------------------------------------------------------------ */
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>

/* Generated menu data — MENU_PROGNAME */
#include "generated/menu.h"

/* Port passed from main() to the app delegate via a global */
static int g_ios_port = 0;
static WKWebView *g_ios_webView = nil;

/* ------------------------------------------------------------------ */
/*  Scene delegate (iOS 13+) — creates the window and web view         */
/* ------------------------------------------------------------------ */
@interface ZSSceneDelegate : UIResponder
    <UIWindowSceneDelegate, WKUIDelegate, WKNavigationDelegate,
     WKScriptMessageHandler, CLLocationManagerDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, copy) void (^locationCallback)(CLLocation *location, NSError *error);
@end

@implementation ZSSceneDelegate
- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)connectionOptions
{
    (void)session; (void)connectionOptions;
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    /* Initialise location manager for native geolocation */
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    if (self.locationManager.authorizationStatus == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }

    /* Full-screen WKWebView */
    WKWebViewConfiguration *config =
        [[WKWebViewConfiguration alloc] init];
    /* Allow inline media playback (no forced fullscreen) */
    config.allowsInlineMediaPlayback = YES;
    [config.userContentController addScriptMessageHandler:self
                                                     name:@"passifloraGeolocation"];
    [config.userContentController addScriptMessageHandler:self
                                                     name:@"passifloraPosix"];

    WKWebView *webView =
        [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    webView.UIDelegate = self;
    webView.navigationDelegate = self;
    g_ios_webView = webView;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = webView;

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    /* Navigate to the local server */
    NSString *urlStr =
        [NSString stringWithFormat:@"http://127.0.0.1:%d/", g_ios_port];
    NSURL *url = [NSURL URLWithString:urlStr];
    [webView loadRequest:[NSURLRequest requestWithURL:url]];
}

/* WKUIDelegate: JavaScript alert() */
- (void)webView:(WKWebView *)wv
    runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(void))completionHandler
{
    (void)wv; (void)frame;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a){
        (void)a;
        completionHandler();
    }]];
    [self.window.rootViewController presentViewController:alert
                                                 animated:YES
                                               completion:nil];
}

/* WKUIDelegate: JavaScript confirm() */
- (void)webView:(WKWebView *)wv
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(BOOL))completionHandler
{
    (void)wv; (void)frame;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a){
        (void)a;
        completionHandler(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a){
        (void)a;
        completionHandler(YES);
    }]];
    [self.window.rootViewController presentViewController:alert
                                                 animated:YES
                                               completion:nil];
}

/* WKUIDelegate: JavaScript prompt() */
- (void)webView:(WKWebView *)wv
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *))completionHandler
{
    (void)wv; (void)frame;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil
                                            message:prompt
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.text = defaultText;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a){
        (void)a;
        completionHandler(nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a){
        (void)a;
        completionHandler(alert.textFields.firstObject.text);
    }]];
    [self.window.rootViewController presentViewController:alert
                                                 animated:YES
                                               completion:nil];
}

/* WKUIDelegate: geolocation permission */
- (void)webView:(WKWebView *)wv
    requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
    initiatedByFrame:(WKFrameInfo *)frame
    decisionHandler:(void (^)(WKPermissionDecision))decisionHandler
    API_AVAILABLE(ios(15.0))
{
    (void)wv; (void)origin; (void)frame;
    decisionHandler(WKPermissionDecisionGrant);
}

/* WKNavigationDelegate: intercept link clicks to external URLs */
- (void)webView:(WKWebView *)wv
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    (void)wv;
    NSURL *url = navigationAction.request.URL;
    if (url && ([url.scheme isEqualToString:@"http"] ||
                [url.scheme isEqualToString:@"https"])) {
        NSString *host = url.host;
        /* Allow navigation to our local server */
        if (host && ([host isEqualToString:@"127.0.0.1"] ||
                     [host isEqualToString:@"localhost"])) {
            decisionHandler(WKNavigationActionPolicyAllow);
            return;
        }
        /* External URL — open in Safari */
        [[UIApplication sharedApplication] openURL:url
            options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

/* CLLocationManagerDelegate: got location */
- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    [manager stopUpdatingLocation];
    CLLocation *loc = [locations lastObject];
    if (self.locationCallback) {
        self.locationCallback(loc, nil);
        self.locationCallback = nil;
    }
}

/* CLLocationManagerDelegate: error */
- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error
{
    [manager stopUpdatingLocation];
    if (self.locationCallback) {
        self.locationCallback(nil, error);
        self.locationCallback = nil;
    }
}

/* Validate callback ID format (geo_N) to prevent JS injection */
static BOOL isValidGeoId(NSString *geoId) {
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"^geo_[0-9]+$" options:0 error:nil];
    return [re numberOfMatchesInString:geoId options:0
        range:NSMakeRange(0, geoId.length)] == 1;
}

/* WKScriptMessageHandler: handle messages from JavaScript */
- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    (void)controller;
    if ([message.name isEqualToString:@"passifloraGeolocation"]) {
        NSString *callbackId = [NSString stringWithFormat:@"%@", message.body];
        if (!isValidGeoId(callbackId)) return;

        CLAuthorizationStatus status = self.locationManager.authorizationStatus;
        if (status == kCLAuthorizationStatusDenied ||
            status == kCLAuthorizationStatusRestricted) {
            NSString *js = [NSString stringWithFormat:
                @"PassifloraIO._geoReject('%@', 1, 'Location permission denied');",
                callbackId];
            [g_ios_webView evaluateJavaScript:js completionHandler:nil];
            return;
        }

        __weak typeof(self) weakSelf = self;
        self.locationCallback = ^(CLLocation *loc, NSError *err) {
            (void)err;
            NSString *js;
            if (loc) {
                js = [NSString stringWithFormat:
                    @"PassifloraIO._geoResolve('%@', %f, %f, %f);",
                    callbackId,
                    loc.coordinate.latitude,
                    loc.coordinate.longitude,
                    loc.horizontalAccuracy];
            } else {
                js = [NSString stringWithFormat:
                    @"PassifloraIO._geoReject('%@', 2, 'Position unavailable');",
                    callbackId];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                (void)weakSelf;
                [g_ios_webView evaluateJavaScript:js completionHandler:nil];
            });
        };
        [self.locationManager requestLocation];
    }
    if ([message.name isEqualToString:@"passifloraPosix"]) {
        NSString *params = [NSString stringWithFormat:@"%@", message.body];
        /* Extract callback ID and validate */
        NSString *cbId = nil;
        for (NSString *pair in [params componentsSeparatedByString:@"&"]) {
            if ([pair hasPrefix:@"id="]) {
                cbId = [pair substringFromIndex:3];
                break;
            }
        }
        if (!cbId) return;
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"^posix_[0-9]+$" options:0 error:nil];
        if ([re numberOfMatchesInString:cbId options:0
                range:NSMakeRange(0, cbId.length)] != 1) return;

        /* Run POSIX call off the main thread */
        NSString *safeParams = [params copy];
        NSString *safeCbId = [cbId copy];
        dispatch_async(dispatch_get_global_queue(
                           DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            extern char *passiflora_posix_call(const char *);
            char *json = passiflora_posix_call(
                [safeParams UTF8String]);
            NSString *jsonStr = json
                ? [NSString stringWithUTF8String:json] : @"{}";
            free(json);
            NSString *js = [NSString stringWithFormat:
                @"PassifloraIO._posixResolve('%@',%@);", safeCbId, jsonStr];
            dispatch_async(dispatch_get_main_queue(), ^{
                [g_ios_webView evaluateJavaScript:js completionHandler:nil];
            });
        });
    }
}
@end

/* ------------------------------------------------------------------ */
/*  App delegate                                                       */
/* ------------------------------------------------------------------ */
@interface ZSAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation ZSAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
    options:(UISceneConnectionOptions *)options
{
    (void)application; (void)options;
    UISceneConfiguration *cfg =
        [[UISceneConfiguration alloc] initWithName:@"Default"
                                       sessionRole:connectingSceneSession.role];
    cfg.delegateClass = [ZSSceneDelegate class];
    return cfg;
}
@end

void ui_open(int port)
{
    g_ios_port = port;
    @autoreleasepool {
        UIApplicationMain(0, (char *[]){""}, nil, NSStringFromClass([ZSAppDelegate class]));
    }
    exit(0);
}

#else
/* ------------------------------------------------------------------ */
/*  macOS — Cocoa + WKWebView                                          */
/* ------------------------------------------------------------------ */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>

/* Generated menu data — menu_template[] and MENU_PROGNAME */
#include "generated/menu.h"

/* Global WKWebView so the menu handler can call JavaScript */
static WKWebView *g_webView = nil;

/* ------------------------------------------------------------------ */
/*  Menu handler — calls PassifloraConfig.handleMenu() in the embedded WKWebView */
/* ------------------------------------------------------------------ */
@interface ZSMenuHandler : NSObject
- (void)menuAction:(id)sender;
@end

@implementation ZSMenuHandler
- (void)menuAction:(id)sender
{
    NSMenuItem *item = (NSMenuItem *)sender;
    if (!g_webView) return;
    NSString *title = [item title];
    /* Escape backslashes and single quotes for JavaScript string */
    title = [title stringByReplacingOccurrencesOfString:@"\\"
                                             withString:@"\\\\"];
    title = [title stringByReplacingOccurrencesOfString:@"'"
                                             withString:@"\\'"];
    NSString *js = [NSString stringWithFormat:
        @"if(typeof PassifloraConfig!=='undefined'&&typeof PassifloraConfig.handleMenu==='function')PassifloraConfig.handleMenu('%@')", title];
    [g_webView evaluateJavaScript:js completionHandler:nil];
}
@end

static ZSMenuHandler *g_menuHandler = nil;

/* ------------------------------------------------------------------ */
/*  Known system menu items — standard selectors & key equivalents     */
/* ------------------------------------------------------------------ */
typedef struct {
    const char *prefix;   /* match from start of title (NULL = end) */
    int         exact;    /* 1 = exact match, 0 = prefix match      */
    SEL         action;
    const char *key;      /* key equivalent (empty string = none)    */
    NSUInteger  mods;     /* 0 = default Cmd, otherwise explicit     */
} sys_menu_item_t;

static SEL sel_for(const char *s) { return NSSelectorFromString(
    [NSString stringWithUTF8String:s]); }

static const struct { const char *prefix; int exact; const char *sel;
    const char *key; int addopt; } known_items[] = {
    { "About",         0, "orderFrontStandardAboutPanel:", "",  0 },
    { "Hide Others",   1, "hideOtherApplications:",        "h", 1 },
    { "Hide",          0, "hide:",                         "h", 0 },
    { "Show All",      1, "unhideAllApplications:",        "",  0 },
    { "Quit",          0, "terminate:",                    "q", 0 },
    { "Undo",          1, "undo:",                         "z", 0 },
    { "Redo",          1, "redo:",                         "Z", 0 },
    { "Cut",           1, "cut:",                          "x", 0 },
    { "Copy",          1, "copy:",                         "c", 0 },
    { "Paste",         1, "paste:",                        "v", 0 },
    { "Select All",    1, "selectAll:",                    "a", 0 },
    { "Close",         1, "performClose:",                 "w", 0 },
    { "Minimize",      1, "performMiniaturize:",           "m", 0 },
    { "Zoom",          1, "performZoom:",                  "",  0 },
    { "Bring All to Front", 1, "arrangeInFront:",          "",  0 },
    { NULL, 0, NULL, NULL, 0 }
};

/* ------------------------------------------------------------------ */
/*  Build menus from the generated menu_template[] array               */
/* ------------------------------------------------------------------ */
static void build_menus(void)
{
    g_menuHandler = [[ZSMenuHandler alloc] init];

    NSMenu *menubar = [[NSMenu alloc] init];

    /*
     * Stack of menus by nesting level:
     *   menuStack[0] = menubar itself (unused as add target)
     *   menuStack[1] = the current top-level dropdown
     *   menuStack[2] = a submenu within level 1, etc.
     */
    #define MAX_MENU_DEPTH 16
    NSMenu *menuStack[MAX_MENU_DEPTH];
    menuStack[0] = menubar;

    for (int i = 0; menu_template[i].level >= 0; i++) {
        int         level = menu_template[i].level;
        const char *text  = menu_template[i].text;
        if (!text) break;

        /* ---- top-level menu bar item ---- */
        if (level == 0) {
            NSMenuItem *barItem = [[NSMenuItem alloc] init];
            [menubar addItem:barItem];
            NSMenu *dropdown = [[NSMenu alloc] initWithTitle:
                [NSString stringWithUTF8String:text]];
            [barItem setSubmenu:dropdown];
            if (level + 1 < MAX_MENU_DEPTH)
                menuStack[level + 1] = dropdown;
            continue;
        }

        /* ---- separator ---- */
        if (strcmp(text, "-") == 0) {
            if (level < MAX_MENU_DEPTH && menuStack[level])
                [menuStack[level] addItem:[NSMenuItem separatorItem]];
            continue;
        }

        /* ---- regular item ---- */
        /* Items prefixed with '*' use the native handler (if one
         * exists).  Items without '*' always go to JavaScript.  */
        int wantNative = (text[0] == '*');
        const char *displayText = wantNative ? text + 1 : text;
        NSString *title = [NSString stringWithUTF8String:displayText];

        SEL action = NULL;
        NSString *keyEq = @"";
        NSUInteger modMask = NSEventModifierFlagCommand;
        int isSystem = 0;

        if (wantNative) {
            /* Look up a known native handler — always exact match
             * so that e.g. *Quite does not match "Quit". */
            for (int k = 0; known_items[k].prefix; k++) {
                const char *p = known_items[k].prefix;
                BOOL match = [title isEqualToString:
                    [NSString stringWithUTF8String:p]];
                if (match) {
                    action  = sel_for(known_items[k].sel);
                    keyEq   = [NSString stringWithUTF8String:known_items[k].key];
                    if (known_items[k].addopt)
                        modMask |= NSEventModifierFlagOption;
                    isSystem = 1;
                    break;
                }
            }
            if (!isSystem) {
                /* No native handler — show a dialog and make the item
                 * a no-op by leaving action = NULL. */
                NSAlert *noHandler = [[NSAlert alloc] init];
                [noHandler setMessageText:
                    [NSString stringWithFormat:
                        @"No native handler for \"%@\" on this platform.", title]];
                [noHandler addButtonWithTitle:@"OK"];
                [noHandler runModal];
                action = NULL;
                keyEq  = @"";
            }
        } else {
            /* No '*' prefix — always route to JavaScript */
            action = @selector(menuAction:);
            keyEq  = @"";
        }

        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:title
                   action:action
            keyEquivalent:keyEq];

        if (isSystem) {
            [item setKeyEquivalentModifierMask:modMask];
        } else if (!wantNative) {
            [item setTarget:g_menuHandler];
        }

        /* Add to the correct parent menu */
        if (level < MAX_MENU_DEPTH && menuStack[level])
            [menuStack[level] addItem:item];

        /* If the next entry is deeper, this item becomes a submenu */
        if (menu_template[i + 1].level > level) {
            NSMenu *sub = [[NSMenu alloc] initWithTitle:title];
            [item setSubmenu:sub];
            if (level + 1 < MAX_MENU_DEPTH)
                menuStack[level + 1] = sub;
        }
    }

    [NSApp setMainMenu:menubar];
}

/* ------------------------------------------------------------------ */
/*  Delegate: quit on window close, WKUIDelegate for JS alert/confirm  */
/* ------------------------------------------------------------------ */
@interface ZSAppDelegate : NSObject
    <NSApplicationDelegate, NSWindowDelegate, WKUIDelegate,
     WKScriptMessageHandler, CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, copy) void (^locationCallback)(CLLocation *location, NSError *error);
@end

@implementation ZSAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    (void)app;
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    (void)note;
    [NSApp activateIgnoringOtherApps:YES];

    /* Initialise location manager for native geolocation */
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    if (self.locationManager.authorizationStatus == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
}

/* CLLocationManagerDelegate: authorisation changed */
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    (void)manager;
    fprintf(stderr, "passiflora: location auth status = %d\n",
            (int)manager.authorizationStatus);
}

/* CLLocationManagerDelegate: got location */
- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    [manager stopUpdatingLocation];
    CLLocation *loc = [locations lastObject];
    if (self.locationCallback) {
        self.locationCallback(loc, nil);
        self.locationCallback = nil;
    }
}

/* CLLocationManagerDelegate: error */
- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error
{
    [manager stopUpdatingLocation];
    if (self.locationCallback) {
        self.locationCallback(nil, error);
        self.locationCallback = nil;
    }
}

/* Validate callback ID format (geo_N) to prevent JS injection */
static BOOL isValidGeoId(NSString *geoId) {
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"^geo_[0-9]+$" options:0 error:nil];
    return [re numberOfMatchesInString:geoId options:0
        range:NSMakeRange(0, geoId.length)] == 1;
}

/* WKScriptMessageHandler: handle messages from JavaScript */
- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    (void)controller;
    if ([message.name isEqualToString:@"passifloraGeolocation"]) {
        NSString *callbackId = [NSString stringWithFormat:@"%@", message.body];
        if (!isValidGeoId(callbackId)) return;

        CLAuthorizationStatus status = self.locationManager.authorizationStatus;
        if (status == kCLAuthorizationStatusDenied ||
            status == kCLAuthorizationStatusRestricted) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Location Services Disabled"];
            [alert setInformativeText:
                @"This app needs access to your location. "
                 "You can enable it in System Settings > "
                 "Privacy & Security > Location Services."];
            [alert addButtonWithTitle:@"Open Settings"];
            [alert addButtonWithTitle:@"Cancel"];
            NSModalResponse resp = [alert runModal];
            if (resp == NSAlertFirstButtonReturn) {
                [[NSWorkspace sharedWorkspace] openURL:
                    [NSURL URLWithString:
                        @"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"]];
            }
            NSString *js = [NSString stringWithFormat:
                @"PassifloraIO._geoReject('%@', 1, 'Location permission denied');",
                callbackId];
            [g_webView evaluateJavaScript:js completionHandler:nil];
            return;
        }

        __weak typeof(self) weakSelf = self;
        self.locationCallback = ^(CLLocation *loc, NSError *err) {
            (void)err;
            NSString *js;
            if (loc) {
                js = [NSString stringWithFormat:
                    @"PassifloraIO._geoResolve('%@', %f, %f, %f);",
                    callbackId,
                    loc.coordinate.latitude,
                    loc.coordinate.longitude,
                    loc.horizontalAccuracy];
            } else {
                js = [NSString stringWithFormat:
                    @"PassifloraIO._geoReject('%@', 2, 'Position unavailable');",
                    callbackId];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                (void)weakSelf;
                [g_webView evaluateJavaScript:js completionHandler:nil];
            });
        };
        [self.locationManager requestLocation];
    }
    if ([message.name isEqualToString:@"passifloraPosix"]) {
        NSString *params = [NSString stringWithFormat:@"%@", message.body];
        NSString *cbId = nil;
        for (NSString *pair in [params componentsSeparatedByString:@"&"]) {
            if ([pair hasPrefix:@"id="]) {
                cbId = [pair substringFromIndex:3];
                break;
            }
        }
        if (!cbId) return;
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:@"^posix_[0-9]+$" options:0 error:nil];
        if ([re numberOfMatchesInString:cbId options:0
                range:NSMakeRange(0, cbId.length)] != 1) return;

        NSString *safeParams = [params copy];
        NSString *safeCbId = [cbId copy];
        dispatch_async(dispatch_get_global_queue(
                           DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            extern char *passiflora_posix_call(const char *);
            char *json = passiflora_posix_call(
                [safeParams UTF8String]);
            NSString *jsonStr = json
                ? [NSString stringWithUTF8String:json] : @"{}";
            free(json);
            NSString *js = [NSString stringWithFormat:
                @"PassifloraIO._posixResolve('%@',%@);", safeCbId, jsonStr];
            dispatch_async(dispatch_get_main_queue(), ^{
                [g_webView evaluateJavaScript:js completionHandler:nil];
            });
        });
    }
}

/* WKUIDelegate: JavaScript alert() */
- (void)webView:(WKWebView *)wv
    runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(void))completionHandler
{
    (void)wv; (void)frame;
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    completionHandler();
}

/* WKUIDelegate: JavaScript confirm() */
- (void)webView:(WKWebView *)wv
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(BOOL))completionHandler
{
    (void)wv; (void)frame;
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse resp = [alert runModal];
    completionHandler(resp == NSAlertFirstButtonReturn);
}

/* WKUIDelegate: JavaScript prompt() */
- (void)webView:(WKWebView *)wv
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *))completionHandler
{
    (void)wv; (void)frame;
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:prompt];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc]
        initWithFrame:NSMakeRect(0, 0, 300, 24)];
    [input setStringValue:(defaultText ? defaultText : @"")];
    [alert setAccessoryView:input];
    NSModalResponse resp = [alert runModal];
    completionHandler(resp == NSAlertFirstButtonReturn
        ? [input stringValue] : nil);
}

/* WKUIDelegate: geolocation permission */
- (void)webView:(WKWebView *)wv
    requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin
    initiatedByFrame:(WKFrameInfo *)frame
    decisionHandler:(void (^)(WKPermissionDecision))decisionHandler
    API_AVAILABLE(macos(12.0))
{
    (void)wv; (void)origin; (void)frame;
    decisionHandler(WKPermissionDecisionGrant);
}

@end

void ui_open(int port)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        /* App delegate — ensures we quit on window close */
        ZSAppDelegate *delegate = [[ZSAppDelegate alloc] init];
        [NSApp setDelegate:delegate];

        /* Build menus from generated menu.c data */
        build_menus();

        /* Window */
        NSRect frame = NSMakeRect(0, 0, 1024, 768);
        NSUInteger style = NSWindowStyleMaskTitled
                         | NSWindowStyleMaskClosable
                         | NSWindowStyleMaskMiniaturizable
                         | NSWindowStyleMaskResizable;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window setTitle:@""];
        [window setTitleVisibility:NSWindowTitleHidden];
        [window setTitlebarAppearsTransparent:YES];
        [window setBackgroundColor:[NSColor colorWithSRGBRed:229/255.0
                                                       green:229/255.0
                                                        blue:229/255.0
                                                       alpha:1.0]];
        [window setDelegate:delegate];
        [window center];

        /* WKWebView filling the entire content area */
        WKWebViewConfiguration *config =
            [[WKWebViewConfiguration alloc] init];
        [config.userContentController addScriptMessageHandler:delegate
                                                         name:@"passifloraGeolocation"];
        [config.userContentController addScriptMessageHandler:delegate
                                                         name:@"passifloraPosix"];
        g_webView =
            [[WKWebView alloc] initWithFrame:[[window contentView] bounds]
                               configuration:config];
        [g_webView setUIDelegate:delegate];
        [g_webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [window setContentView:g_webView];

        /* Navigate to the local server */
        NSString *urlStr =
            [NSString stringWithFormat:@"http://127.0.0.1:%d/", port];
        NSURL *url = [NSURL URLWithString:urlStr];
        [g_webView loadRequest:[NSURLRequest requestWithURL:url]];

        /* Show and run */
        [window makeKeyAndOrderFront:nil];
        [NSApp run];  /* blocks until termination */
    }

    exit(0);
}

#endif /* TARGET_OS_IPHONE */

/* ================================================================== */
/*  Windows                                                            */
/* ================================================================== */
#elif defined(_WIN32)
/* ------------------------------------------------------------------ */
/*  Windows — Win32 window + embedded Edge WebView2                    */
/* ------------------------------------------------------------------ */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>
#include <ole2.h>

/* Generated menu data — MENU_PROGNAME, menu_template[] */
#include "generated/win_menu.h"

/* ---- GUIDs for WebView2 COM interfaces ---- */
/* (some referenced only in callback IID matching) */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-const-variable"
static const IID IID_ICoreWebView2Environment = {
    0xb96d755e,0x0319,0x4e92,
    {0xa2,0x96,0x23,0x43,0x6f,0x46,0xa1,0xfc}};
static const IID IID_ICoreWebView2Controller = {
    0x4d00c0d1,0x9434,0x4eb6,
    {0x80,0x78,0x86,0x97,0xa5,0x60,0x33,0x4f}};
static const IID IID_ICoreWebView2 = {
    0x76eceacb,0x0462,0x4d94,
    {0xac,0x83,0x42,0x3a,0x67,0x93,0x77,0x5e}};
#pragma GCC diagnostic pop

/* ---- Minimal COM vtable definitions (C style) ---- */
/*  We only declare entries up to the ones we actually call.           */

/* -- ICoreWebView2 ------------------------------------------------ */
typedef struct ICoreWebView2 ICoreWebView2;
typedef struct {
    /* IUnknown */
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        ICoreWebView2*,REFIID,void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(ICoreWebView2*);
    ULONG   (STDMETHODCALLTYPE *Release)(ICoreWebView2*);
    /* ICoreWebView2 */
    HRESULT (STDMETHODCALLTYPE *get_Settings)(
        ICoreWebView2*,void**);           /* 3 */
    HRESULT (STDMETHODCALLTYPE *get_Source)(
        ICoreWebView2*,LPWSTR*);          /* 4 */
    HRESULT (STDMETHODCALLTYPE *Navigate)(
        ICoreWebView2*,LPCWSTR);          /* 5 */
    HRESULT (STDMETHODCALLTYPE *NavigateToString)(
        ICoreWebView2*,LPCWSTR);          /* 6 */
    void *_pad7;   /* add_NavigationStarting */
    void *_pad8;   /* remove_NavigationStarting */
    void *_pad9;   /* add_ContentLoading */
    void *_pad10;  /* remove_ContentLoading */
    void *_pad11;  /* add_SourceChanged */
    void *_pad12;  /* remove_SourceChanged */
    void *_pad13;  /* add_HistoryChanged */
    void *_pad14;  /* remove_HistoryChanged */
    HRESULT (STDMETHODCALLTYPE *add_NavigationCompleted)(
        ICoreWebView2*,void*,void*);      /* 15 */
    void *_pad16;  /* remove_NavigationCompleted */
    void *_pad17;  /* add_FrameNavigationStarting */
    void *_pad18;  /* remove_FrameNavigationStarting */
    void *_pad19;  /* add_FrameNavigationCompleted */
    void *_pad20;  /* remove_FrameNavigationCompleted */
    void *_pad21;  /* add_ScriptDialogOpening */
    void *_pad22;  /* remove_ScriptDialogOpening */
    HRESULT (STDMETHODCALLTYPE *add_PermissionRequested)(
        ICoreWebView2*,void*,void*);      /* 23 */
    void *_pad24;  /* remove_PermissionRequested */
    void *_pad25;  /* add_ProcessFailed */
    void *_pad26;  /* remove_ProcessFailed */
    void *_pad27;  /* AddScriptToExecuteOnDocumentCreated */
    void *_pad28;  /* RemoveScriptToExecuteOnDocumentCreated */
    HRESULT (STDMETHODCALLTYPE *ExecuteScript)(
        ICoreWebView2*,LPCWSTR,void*);    /* 29 */
    void *_pad30;  /* CapturePreview */
    void *_pad31;  /* Reload */
    void *_pad32;  /* PostWebMessageAsJson */
    void *_pad33;  /* PostWebMessageAsString */
    HRESULT (STDMETHODCALLTYPE *add_WebMessageReceived)(
        ICoreWebView2*,void*,void*);      /* 34 */
} ICoreWebView2Vtbl;
struct ICoreWebView2 { ICoreWebView2Vtbl *lpVtbl; };

/* -- ICoreWebView2Settings ---------------------------------------- */
typedef struct ICoreWebView2Settings ICoreWebView2Settings;
typedef struct {
    /* IUnknown */
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        ICoreWebView2Settings*,REFIID,void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(ICoreWebView2Settings*);
    ULONG   (STDMETHODCALLTYPE *Release)(ICoreWebView2Settings*);
    /* ICoreWebView2Settings */
    HRESULT (STDMETHODCALLTYPE *get_IsScriptEnabled)(
        ICoreWebView2Settings*,BOOL*);
    HRESULT (STDMETHODCALLTYPE *put_IsScriptEnabled)(
        ICoreWebView2Settings*,BOOL);
    void *_pad5;   /* get_IsWebMessageEnabled */
    void *_pad6;   /* put_IsWebMessageEnabled */
    HRESULT (STDMETHODCALLTYPE *get_AreDefaultScriptDialogsEnabled)(
        ICoreWebView2Settings*,BOOL*);
    HRESULT (STDMETHODCALLTYPE *put_AreDefaultScriptDialogsEnabled)(
        ICoreWebView2Settings*,BOOL);
} ICoreWebView2SettingsVtbl;
struct ICoreWebView2Settings { ICoreWebView2SettingsVtbl *lpVtbl; };

/* -- ICoreWebView2Controller -------------------------------------- */
typedef struct ICoreWebView2Controller ICoreWebView2Controller;
typedef struct {
    /* IUnknown (0-2) */
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        ICoreWebView2Controller*,REFIID,void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(ICoreWebView2Controller*);
    ULONG   (STDMETHODCALLTYPE *Release)(ICoreWebView2Controller*);
    /* 3  */ void *get_IsVisible;
    /* 4  */ void *put_IsVisible;
    /* 5  */ void *get_Bounds;
    /* 6  */ HRESULT (STDMETHODCALLTYPE *put_Bounds)(
                 ICoreWebView2Controller*,RECT);
    /* 7  */ void *get_ZoomFactor;
    /* 8  */ void *put_ZoomFactor;
    /* 9  */ void *add_ZoomFactorChanged;
    /* 10 */ void *remove_ZoomFactorChanged;
    /* 11 */ void *SetBoundsAndZoomFactor;
    /* 12 */ void *MoveFocus;
    /* 13 */ void *add_MoveFocusRequested;
    /* 14 */ void *remove_MoveFocusRequested;
    /* 15 */ void *add_GotFocus;
    /* 16 */ void *remove_GotFocus;
    /* 17 */ void *add_LostFocus;
    /* 18 */ void *remove_LostFocus;
    /* 19 */ void *add_AcceleratorKeyPressed;
    /* 20 */ void *remove_AcceleratorKeyPressed;
    /* 21 */ void *get_ParentWindow;
    /* 22 */ void *put_ParentWindow;
    /* 23 */ void *NotifyParentWindowPositionChanged;
    /* 24 */ void *Close;
    /* 25 */ HRESULT (STDMETHODCALLTYPE *get_CoreWebView2)(
                 ICoreWebView2Controller*,ICoreWebView2**);
} ICoreWebView2ControllerVtbl;
struct ICoreWebView2Controller { ICoreWebView2ControllerVtbl *lpVtbl; };

/* -- ICoreWebView2Environment ------------------------------------- */
typedef struct ICoreWebView2Environment ICoreWebView2Environment;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        ICoreWebView2Environment*,REFIID,void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(ICoreWebView2Environment*);
    ULONG   (STDMETHODCALLTYPE *Release)(ICoreWebView2Environment*);
    HRESULT (STDMETHODCALLTYPE *CreateCoreWebView2Controller)(
        ICoreWebView2Environment*,HWND,void*);
} ICoreWebView2EnvironmentVtbl;
struct ICoreWebView2Environment { ICoreWebView2EnvironmentVtbl *lpVtbl; };

/* -- ICoreWebView2PermissionRequestedEventArgs -------------------- */
typedef struct ICoreWebView2PermissionRequestedEventArgs
    ICoreWebView2PermissionRequestedEventArgs;
typedef struct {
    /* IUnknown */
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        ICoreWebView2PermissionRequestedEventArgs*,REFIID,void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(
        ICoreWebView2PermissionRequestedEventArgs*);
    ULONG   (STDMETHODCALLTYPE *Release)(
        ICoreWebView2PermissionRequestedEventArgs*);
    /* ICoreWebView2PermissionRequestedEventArgs */
    HRESULT (STDMETHODCALLTYPE *get_Uri)(
        ICoreWebView2PermissionRequestedEventArgs*,LPWSTR*);  /* 3 */
    HRESULT (STDMETHODCALLTYPE *get_PermissionKind)(
        ICoreWebView2PermissionRequestedEventArgs*,int*);     /* 4 */
    HRESULT (STDMETHODCALLTYPE *get_IsUserInitiated)(
        ICoreWebView2PermissionRequestedEventArgs*,BOOL*);    /* 5 */
    HRESULT (STDMETHODCALLTYPE *get_State)(
        ICoreWebView2PermissionRequestedEventArgs*,int*);     /* 6 */
    HRESULT (STDMETHODCALLTYPE *put_State)(
        ICoreWebView2PermissionRequestedEventArgs*,int);      /* 7 */
} ICoreWebView2PermissionRequestedEventArgsVtbl;
struct ICoreWebView2PermissionRequestedEventArgs {
    ICoreWebView2PermissionRequestedEventArgsVtbl *lpVtbl;
};

/* -- ICoreWebView2WebMessageReceivedEventArgs --------------------- */
typedef struct ICoreWebView2WebMessageReceivedEventArgs
    ICoreWebView2WebMessageReceivedEventArgs;
typedef struct {
    /* IUnknown */
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        ICoreWebView2WebMessageReceivedEventArgs*,REFIID,void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(
        ICoreWebView2WebMessageReceivedEventArgs*);
    ULONG   (STDMETHODCALLTYPE *Release)(
        ICoreWebView2WebMessageReceivedEventArgs*);
    /* ICoreWebView2WebMessageReceivedEventArgs */
    HRESULT (STDMETHODCALLTYPE *get_Source)(
        ICoreWebView2WebMessageReceivedEventArgs*,LPWSTR*);   /* 3 */
    HRESULT (STDMETHODCALLTYPE *get_WebMessageAsJson)(
        ICoreWebView2WebMessageReceivedEventArgs*,LPWSTR*);   /* 4 */
    HRESULT (STDMETHODCALLTYPE *TryGetWebMessageAsString)(
        ICoreWebView2WebMessageReceivedEventArgs*,LPWSTR*);   /* 5 */
} ICoreWebView2WebMessageReceivedEventArgsVtbl;
struct ICoreWebView2WebMessageReceivedEventArgs {
    ICoreWebView2WebMessageReceivedEventArgsVtbl *lpVtbl;
};

/* ---- Callback handler structs ---- */
/*  COM callbacks: IUnknown { QI, AddRef, Release } + Invoke.
 *  We use a single generic layout for both handlers.                  */

typedef struct WV2Handler WV2Handler;
typedef HRESULT (STDMETHODCALLTYPE *WV2InvokeFn)(
    WV2Handler*, HRESULT, void*);

typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(
        WV2Handler*, REFIID, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(WV2Handler*);
    ULONG   (STDMETHODCALLTYPE *Release)(WV2Handler*);
    WV2InvokeFn Invoke;
} WV2HandlerVtbl;

struct WV2Handler {
    WV2HandlerVtbl *lpVtbl;
    LONG            refCount;
    IID             iid;       /* which handler interface this is */
    void           *context;   /* user data (our WV2State) */
};

/* ---- Application state ---- */
#define WIN_MENU_ID_BASE  9000
#define WIN_MENU_MAX_ITEMS 256

typedef struct {
    HWND                        hwnd;
    int                         port;
    ICoreWebView2Environment   *env;
    ICoreWebView2Controller    *ctrl;
    ICoreWebView2              *webview;
    /* Menu item title lookup (command ID = WIN_MENU_ID_BASE + index) */
    const char                 *menuTitles[WIN_MENU_MAX_ITEMS];
    int                         menuCount;
    HMENU                       hMenu;     /* stored for Alt toggle */
    int                         menuVisible;
} WV2State;

static WV2State g_wv2 = {0};

/* ---- Handler IUnknown implementation ---- */
static HRESULT STDMETHODCALLTYPE
Handler_QueryInterface(WV2Handler *self, REFIID riid, void **ppv)
{
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid, &self->iid)) {
        *ppv = self;
        self->lpVtbl->AddRef(self);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE Handler_AddRef(WV2Handler *self)
{
    return InterlockedIncrement(&self->refCount);
}

static ULONG STDMETHODCALLTYPE Handler_Release(WV2Handler *self)
{
    LONG rc = InterlockedDecrement(&self->refCount);
    if (rc == 0) free(self);
    return rc;
}

/* ---- Forward declarations for Invoke callbacks ---- */
static HRESULT STDMETHODCALLTYPE
OnControllerCreated(WV2Handler*, HRESULT, void*);

/* GUIDs for handler interfaces */
static const IID IID_EnvCompletedHandler = {
    0x4e8a3389,0xc9d8,0x4bd2,
    {0xb6,0xb5,0x12,0x4f,0xee,0x6c,0xc1,0x4d}};
static const IID IID_CtrlCompletedHandler = {
    0x6c4819f3,0xc9b7,0x4260,
    {0x81,0x27,0xc9,0xf5,0xe7,0xa7,0x53,0x12}};
static const IID IID_PermissionRequestedHandler = {
    0x15e1c6a3,0xc72a,0x4df3,
    {0x91,0xd7,0xd0,0x97,0xfb,0xec,0x6b,0xfd}};
static const IID IID_WebMessageReceivedHandler = {
    0x57213f19,0x00a6,0x49f7,
    {0xa9,0x14,0x0d,0x4e,0x74,0xe7,0xa3,0xb0}};

/* ---- Invoke: environment created ---- */
static HRESULT STDMETHODCALLTYPE
OnEnvironmentCreated(WV2Handler *self, HRESULT hr, void *env)
{
    if (FAILED(hr) || !env) return hr;
    WV2State *st = (WV2State *)self->context;
    st->env = (ICoreWebView2Environment *)env;
    st->env->lpVtbl->AddRef(st->env);

    /* Allocate the controller-completed handler */
    WV2Handler *ch = calloc(1, sizeof *ch);
    static WV2HandlerVtbl ctrlVtbl = {
        Handler_QueryInterface, Handler_AddRef,
        Handler_Release,
        (WV2InvokeFn)OnControllerCreated
    };
    ch->lpVtbl   = &ctrlVtbl;
    ch->refCount = 1;
    ch->iid      = IID_CtrlCompletedHandler;
    ch->context  = st;

    st->env->lpVtbl->CreateCoreWebView2Controller(
        st->env, st->hwnd, (void *)ch);
    ch->lpVtbl->Release(ch);
    return S_OK;
}

/* ---- Invoke: permission requested ---- */
static HRESULT STDMETHODCALLTYPE
OnPermissionRequested(WV2Handler *self, HRESULT sender_unused, void *argsRaw)
{
    (void)self; (void)sender_unused;
    ICoreWebView2PermissionRequestedEventArgs *args =
        (ICoreWebView2PermissionRequestedEventArgs *)argsRaw;
    int kind = 0;
    args->lpVtbl->get_PermissionKind(args, &kind);
    /* COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION = 3 */
    if (kind == 3) {
        /* COREWEBVIEW2_PERMISSION_STATE_ALLOW = 1 */
        args->lpVtbl->put_State(args, 1);
    }
    return S_OK;
}

/* Validate posix callback ID (posix_N) */
static int is_valid_posix_id_w(const char *id)
{
    if (!id || strncmp(id, "posix_", 6) != 0) return 0;
    const char *p = id + 6;
    if (*p == '\0') return 0;
    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }
    return 1;
}

/* POSIX call thread data for Windows */
typedef struct {
    char *params;
    char *cb_id;
    WV2State *st;
} WinPosixTask;

/* Custom window message: LPARAM = heap-allocated wchar_t* JS to execute */
#define WM_POSIX_RESULT (WM_APP + 1)

static DWORD WINAPI win_posix_thread(LPVOID data)
{
    WinPosixTask *task = (WinPosixTask *)data;
    extern char *passiflora_posix_call(const char *);
    char *json = passiflora_posix_call(task->params);
    if (!json) json = _strdup("{}");

    /* Build JS callback: PassifloraIO._posixResolve('id', {json}) */
    size_t jlen = strlen(task->cb_id) + strlen(json) + 64;
    char *js8 = (char *)malloc(jlen);
    if (js8) {
        snprintf(js8, jlen,
            "PassifloraIO._posixResolve('%s',%s);",
            task->cb_id, json);
        int wlen = MultiByteToWideChar(CP_UTF8, 0, js8, -1, NULL, 0);
        wchar_t *wjs = (wchar_t *)malloc(wlen * sizeof(wchar_t));
        if (wjs) {
            MultiByteToWideChar(CP_UTF8, 0, js8, -1, wjs, wlen);
            /* Post to UI thread — ExecuteScript must run on the UI thread */
            if (task->st->hwnd)
                PostMessage(task->st->hwnd, WM_POSIX_RESULT, 0, (LPARAM)wjs);
            else
                free(wjs);
        }
        free(js8);
    }
    free(json);
    free(task->params);
    free(task->cb_id);
    free(task);
    return 0;
}

/* ---- Invoke: web message received ---- */
static HRESULT STDMETHODCALLTYPE
OnWebMessageReceived(WV2Handler *self, HRESULT sender_unused, void *argsRaw)
{
    (void)sender_unused;
    WV2State *st = (WV2State *)self->context;
    ICoreWebView2WebMessageReceivedEventArgs *args =
        (ICoreWebView2WebMessageReceivedEventArgs *)argsRaw;

    LPWSTR wmsg = NULL;
    if (FAILED(args->lpVtbl->TryGetWebMessageAsString(args, &wmsg)) || !wmsg)
        return S_OK;

    /* Convert wide string to UTF-8 */
    int ulen = WideCharToMultiByte(CP_UTF8, 0, wmsg, -1, NULL, 0, NULL, NULL);
    char *params = (char *)malloc(ulen);
    if (!params) { CoTaskMemFree(wmsg); return S_OK; }
    WideCharToMultiByte(CP_UTF8, 0, wmsg, -1, params, ulen, NULL, NULL);
    CoTaskMemFree(wmsg);

    /* Extract id= from URL-encoded params */
    char *cb_id = NULL;
    char *p = params;
    while (*p) {
        if (strncmp(p, "id=", 3) == 0) {
            p += 3;
            const char *end = strchr(p, '&');
            size_t len = end ? (size_t)(end - p) : strlen(p);
            cb_id = (char *)malloc(len + 1);
            if (cb_id) { memcpy(cb_id, p, len); cb_id[len] = '\0'; }
            break;
        }
        const char *amp = strchr(p, '&');
        if (!amp) break;
        p = (char *)amp + 1;
    }

    if (!cb_id || !is_valid_posix_id_w(cb_id)) {
        free(cb_id);
        free(params);
        return S_OK;
    }

    /* Run POSIX call on a worker thread to avoid blocking UI */
    WinPosixTask *task = (WinPosixTask *)calloc(1, sizeof(WinPosixTask));
    if (task) {
        task->params = params;
        task->cb_id = cb_id;
        task->st = st;
        HANDLE h = CreateThread(NULL, 0, win_posix_thread, task, 0, NULL);
        if (h) CloseHandle(h);
        else { free(params); free(cb_id); free(task); }
    } else { free(params); free(cb_id); }

    return S_OK;
}

/* ---- Invoke: controller created ---- */
static HRESULT STDMETHODCALLTYPE
OnControllerCreated(WV2Handler *self, HRESULT hr, void *ctrl)
{
    if (FAILED(hr) || !ctrl) return hr;
    WV2State *st = (WV2State *)self->context;
    st->ctrl = (ICoreWebView2Controller *)ctrl;
    st->ctrl->lpVtbl->AddRef(st->ctrl);

    /* Fill the window */
    RECT rc;
    GetClientRect(st->hwnd, &rc);
    st->ctrl->lpVtbl->put_Bounds(st->ctrl, rc);

    /* Get the webview */
    st->ctrl->lpVtbl->get_CoreWebView2(st->ctrl, &st->webview);

    /* Enable script + default dialogs */
    ICoreWebView2Settings *settings = NULL;
    st->webview->lpVtbl->get_Settings(st->webview, (void **)&settings);
    if (settings) {
        settings->lpVtbl->put_IsScriptEnabled(settings, TRUE);
        settings->lpVtbl->put_AreDefaultScriptDialogsEnabled(
            settings, TRUE);
        settings->lpVtbl->Release(settings);
    }

    /* Auto-grant geolocation permission requests */
    {
        WV2Handler *ph = calloc(1, sizeof *ph);
        static WV2HandlerVtbl permVtbl = {
            Handler_QueryInterface, Handler_AddRef,
            Handler_Release,
            (WV2InvokeFn)OnPermissionRequested
        };
        ph->lpVtbl   = &permVtbl;
        ph->refCount = 1;
        ph->iid      = IID_PermissionRequestedHandler;
        ph->context  = st;
        st->webview->lpVtbl->add_PermissionRequested(
            st->webview, (void *)ph, NULL);
        ph->lpVtbl->Release(ph);
    }

    /* Listen for web messages from JavaScript (POSIX bridge) */
    {
        WV2Handler *mh = calloc(1, sizeof *mh);
        static WV2HandlerVtbl msgVtbl = {
            Handler_QueryInterface, Handler_AddRef,
            Handler_Release,
            (WV2InvokeFn)OnWebMessageReceived
        };
        mh->lpVtbl   = &msgVtbl;
        mh->refCount = 1;
        mh->iid      = IID_WebMessageReceivedHandler;
        mh->context  = st;
        st->webview->lpVtbl->add_WebMessageReceived(
            st->webview, (void *)mh, NULL);
        mh->lpVtbl->Release(mh);
    }

    /* Navigate */
    wchar_t url[256];
    _snwprintf(url, 256, L"http://127.0.0.1:%d/", st->port);
    st->webview->lpVtbl->Navigate(st->webview, url);
    return S_OK;
}

/* ---- Build Win32 menu bar from menu_template[] ---- */
static HMENU build_win32_menus(WV2State *st)
{
    HMENU menubar = CreateMenu();
    #define MAX_WIN_MENU_DEPTH 16
    HMENU stack[MAX_WIN_MENU_DEPTH];
    stack[0] = menubar;
    st->menuCount = 0;

    for (int i = 0; menu_template[i].level >= 0; i++) {
        int         level = menu_template[i].level;
        const char *text  = menu_template[i].text;
        if (!text) break;

        /* Items prefixed with '*' are native-only; strip the prefix
         * for display.  Items without '*' go to JavaScript.        */
        int wantNative = (text[0] == '*');
        const char *displayText = wantNative ? text + 1 : text;

        /* Top-level menu bar item (level 0) */
        if (level == 0) {
            HMENU popup = CreatePopupMenu();
            AppendMenuA(menubar, MF_POPUP, (UINT_PTR)popup, displayText);
            if (level + 1 < MAX_WIN_MENU_DEPTH)
                stack[level + 1] = popup;
            continue;
        }

        /* Separator */
        if (strcmp(displayText, "-") == 0) {
            if (level < MAX_WIN_MENU_DEPTH && stack[level])
                AppendMenuA(stack[level], MF_SEPARATOR, 0, NULL);
            continue;
        }

        /* Check if next entry is deeper => this becomes a submenu */
        if (menu_template[i + 1].level > level) {
            HMENU sub = CreatePopupMenu();
            if (level < MAX_WIN_MENU_DEPTH && stack[level])
                AppendMenuA(stack[level], MF_POPUP, (UINT_PTR)sub, displayText);
            if (level + 1 < MAX_WIN_MENU_DEPTH)
                stack[level + 1] = sub;
            continue;
        }

        /* Regular leaf item — assign a command ID */
        int idx = st->menuCount;
        if (idx < WIN_MENU_MAX_ITEMS) {
            /* Store the original text (with '*' if present) so the
             * WM_COMMAND handler knows whether this is native. */
            st->menuTitles[idx] = text;
            st->menuCount++;
            if (level < MAX_WIN_MENU_DEPTH && stack[level])
                AppendMenuA(stack[level], MF_STRING,
                            WIN_MENU_ID_BASE + idx, displayText);
        }
    }
    #undef MAX_WIN_MENU_DEPTH
    return menubar;
}

/* ---- Call PassifloraConfig.handleMenu() in the WebView ---- */
static void win_call_handlemenu(WV2State *st, const char *title)
{
    if (!st->webview) return;

    /* Build JS: if(typeof PassifloraConfig!=='undefined'...)PassifloraConfig.handleMenu('...') */
    /* Escape backslashes and single quotes */
    char escaped[512];
    int j = 0;
    for (int i = 0; title[i] && j < (int)sizeof(escaped) - 2; i++) {
        if (title[i] == '\\' || title[i] == '\'') {
            if (j < (int)sizeof(escaped) - 3) escaped[j++] = '\\';
        }
        escaped[j++] = title[i];
    }
    escaped[j] = '\0';

    char js8[1024];
    snprintf(js8, sizeof js8,
        "if(typeof PassifloraConfig!=='undefined'&&typeof PassifloraConfig.handleMenu==='function')PassifloraConfig.handleMenu('%s')", escaped);

    /* Convert UTF-8 script to wide string for ExecuteScript */
    int wlen = MultiByteToWideChar(CP_UTF8, 0, js8, -1, NULL, 0);
    wchar_t *wjs = (wchar_t *)_alloca(wlen * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, js8, -1, wjs, wlen);

    st->webview->lpVtbl->ExecuteScript(st->webview, wjs, NULL);
}

/* ---- Helper: resize WebView after menu show/hide ---- */
static void wv2_resize_to_client(HWND hwnd)
{
    if (g_wv2.ctrl) {
        RECT rc;
        GetClientRect(hwnd, &rc);
        g_wv2.ctrl->lpVtbl->put_Bounds(g_wv2.ctrl, rc);
    }
}

/* ---- Window procedure ---- */
static LRESULT CALLBACK ZSWndProc(HWND hwnd, UINT msg,
                                  WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_SIZE:
        wv2_resize_to_client(hwnd);
        return 0;
    case WM_COMMAND: {
        int id = LOWORD(wp);
        int idx = id - WIN_MENU_ID_BASE;
        if (idx >= 0 && idx < g_wv2.menuCount && g_wv2.menuTitles[idx]) {
            const char *raw = g_wv2.menuTitles[idx];
            if (raw[0] == '*') {
                /* Native-only item: handle known actions */
                const char *name = raw + 1;
                if (_stricmp(name, "Quit") == 0 ||
                    _stricmp(name, "Exit") == 0) {
                    PostMessage(hwnd, WM_CLOSE, 0, 0);
                } else {
                    MessageBoxA(hwnd,
                        "No native handler for this item on this platform.",
                        name, MB_OK | MB_ICONINFORMATION);
                }
            } else {
                win_call_handlemenu(&g_wv2, raw);
            }
        }
        /* Hide menu after selection */
        if (g_wv2.menuVisible) {
            g_wv2.menuVisible = 0;
            SetMenu(hwnd, NULL);
            wv2_resize_to_client(hwnd);
        }
        return 0;
    }
    case WM_SYSCOMMAND:
        /* SC_KEYMENU fires on Alt press-release or Alt+letter.
         * wp = 0 means bare Alt/F10, otherwise it's a mnemonic char. */
        if ((wp & 0xFFF0) == SC_KEYMENU) {
            if (!g_wv2.menuVisible) {
                g_wv2.menuVisible = 1;
                SetMenu(hwnd, g_wv2.hMenu);
                wv2_resize_to_client(hwnd);
            }
            /* Let DefWindowProc handle the actual menu activation */
            break;
        }
        break;
    case WM_EXITMENULOOP:
        /* Menu interaction finished (Escape, click-away, or item picked) */
        if (g_wv2.menuVisible) {
            g_wv2.menuVisible = 0;
            SetMenu(hwnd, NULL);
            wv2_resize_to_client(hwnd);
        }
        return 0;
    case WM_POSIX_RESULT: {
        /* ExecuteScript callback from worker thread */
        wchar_t *wjs = (wchar_t *)lp;
        if (wjs) {
            if (g_wv2.webview)
                g_wv2.webview->lpVtbl->ExecuteScript(
                    g_wv2.webview, wjs, NULL);
            free(wjs);
        }
        return 0;
    }
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

/* ---- Entry point ---- */
void ui_open(int port)
{
    g_wv2.port = port;

    OleInitialize(NULL);
    HINSTANCE hInst = GetModuleHandle(NULL);

    WNDCLASSEXA wc;
    memset(&wc, 0, sizeof wc);
    wc.cbSize        = sizeof wc;
    wc.lpfnWndProc   = ZSWndProc;
    wc.hInstance     = hInst;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "PassifloraWnd";
    wc.hIcon         = LoadIconA(hInst, MAKEINTRESOURCEA(1));
    wc.hIconSm       = (HICON)LoadImageA(hInst, MAKEINTRESOURCEA(1),
                            IMAGE_ICON,
                            GetSystemMetrics(SM_CXSMICON),
                            GetSystemMetrics(SM_CYSMICON),
                            LR_DEFAULTCOLOR);
    RegisterClassExA(&wc);

    g_wv2.hwnd = CreateWindowExA(
        0, "PassifloraWnd", "",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 1024, 768,
        NULL, NULL, hInst, NULL);

    /* Build menu bar (hidden until Alt is pressed) */
    g_wv2.hMenu = build_win32_menus(&g_wv2);
    g_wv2.menuVisible = 0;

    ShowWindow(g_wv2.hwnd, SW_SHOW);
    UpdateWindow(g_wv2.hwnd);

    /* ---- Load embedded WebView2Loader.dll ---- */
    /*  The DLL bytes are compiled into the binary via wv2loader.h.
     *  We write them to a temp file so LoadLibrary can use them.     */
#include "wv2loader.h"

    typedef HRESULT (STDMETHODCALLTYPE *PFN_CreateEnv)(
        LPCWSTR, LPCWSTR, void*, void*);
    PFN_CreateEnv pfnCreateEnv = NULL;

    char dllPath[MAX_PATH + 32] = {0};
    {
        char tmpDir[MAX_PATH];
        DWORD tlen = GetTempPathA(MAX_PATH, tmpDir);
        if (tlen > 0 && tlen < MAX_PATH)
            snprintf(dllPath, sizeof dllPath,
                     "%sWebView2Loader.dll", tmpDir);
        HANDLE hf = CreateFileA(dllPath, GENERIC_WRITE, 0, NULL,
                                CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (hf != INVALID_HANDLE_VALUE) {
            DWORD written;
            WriteFile(hf, wv2loader_dll, wv2loader_dll_len,
                      &written, NULL);
            CloseHandle(hf);
        }
    }

    HMODULE hWV2 = LoadLibraryA(dllPath);
    if (hWV2)
        pfnCreateEnv = (PFN_CreateEnv)(void *)GetProcAddress(
            hWV2, "CreateCoreWebView2EnvironmentWithOptions");

    if (!pfnCreateEnv) {
        /* Fallback: open in default browser */
        char url[256];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        ShellExecuteA(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
        /* Keep window alive with a simple message */
        HDC hdc = GetDC(g_wv2.hwnd);
        SetBkMode(hdc, TRANSPARENT);
        RECT rc; GetClientRect(g_wv2.hwnd, &rc);
        DrawTextA(hdc, "WebView2Loader.dll not found — "
                       "opened in default browser", -1, &rc,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        ReleaseDC(g_wv2.hwnd, hdc);
    } else {
        /* Create environment-completed handler */
        WV2Handler *eh = calloc(1, sizeof *eh);
        static WV2HandlerVtbl envVtbl = {
            Handler_QueryInterface, Handler_AddRef,
            Handler_Release,
            (WV2InvokeFn)OnEnvironmentCreated
        };
        eh->lpVtbl   = &envVtbl;
        eh->refCount = 1;
        eh->iid      = IID_EnvCompletedHandler;
        eh->context  = &g_wv2;

        pfnCreateEnv(NULL, NULL, NULL, (void *)eh);
        eh->lpVtbl->Release(eh);
    }

    /* Message loop — blocks until window closed */
    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    OleUninitialize();
    ExitProcess(0);
}

/* ================================================================== */
/*  Android                                                            */
/* ================================================================== */
#elif defined(__ANDROID__)

/* On Android the UI is managed by Java (MainActivity + WebView).
   The native server is started via JNI in passiflora.c.             */
void ui_open(int port)
{
    (void)port;
}

/* ================================================================== */
/*  Linux — GTK3 + WebKitGTK                                           */
/* ================================================================== */
#elif defined(__linux__)

#include <gtk/gtk.h>
#include <glib/gstdio.h>
#include <webkit2/webkit2.h>
#include <string.h>
#include <limits.h>

/* Generated menu data — MENU_PROGNAME, menu_template[] */
#include "generated/menu.h"

/* Embedded app icon PNG (generated at build time) */
#include "generated/linux_icon.h"

static WebKitWebView *g_linux_webview = NULL;

/* ---- Call PassifloraConfig.handleMenu() in the WebView ---- */
static void linux_call_handlemenu(const char *title)
{
    if (!g_linux_webview) return;

    /* Escape backslashes and single quotes for JS string */
    char escaped[512];
    int j = 0;
    for (int i = 0; title[i] && j < (int)sizeof(escaped) - 2; i++) {
        if (title[i] == '\\' || title[i] == '\'')
            if (j < (int)sizeof(escaped) - 3) escaped[j++] = '\\';
        escaped[j++] = title[i];
    }
    escaped[j] = '\0';

    char js[1024];
    snprintf(js, sizeof js,
        "if(typeof PassifloraConfig!=='undefined'&&typeof PassifloraConfig.handleMenu==='function')PassifloraConfig.handleMenu('%s')", escaped);

    webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                        NULL, NULL, NULL, NULL, NULL);
}

/* ---- Menu item callbacks ---- */
static void on_menu_item_activate(GtkMenuItem *item, gpointer data)
{
    (void)item;
    linux_call_handlemenu((const char *)data);
}

static void on_quit_activate(GtkMenuItem *item, gpointer data)
{
    (void)item; (void)data;
    gtk_main_quit();
}

/* ---- Native-only callback: show "no handler" dialog ---- */
static void on_no_native_handler(GtkMenuItem *item, gpointer data)
{
    (void)item;
    const char *name = (const char *)data;
    GtkWidget *dialog = gtk_message_dialog_new(
        NULL, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_OK,
        "No native handler for \"%s\" on this platform.", name);
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
}

/* ---- Build GTK menu bar from menu_template[] ---- */
static GtkWidget *build_gtk_menus(void)
{
    GtkWidget *menubar = gtk_menu_bar_new();

    #define MAX_GTK_MENU_DEPTH 16
    GtkWidget *stack[MAX_GTK_MENU_DEPTH];
    stack[0] = menubar;

    for (int i = 0; menu_template[i].level >= 0; i++) {
        int         level = menu_template[i].level;
        const char *text  = menu_template[i].text;
        if (!text) break;

        /* Items prefixed with '*' use native handlers only;
         * items without '*' are routed to JavaScript.       */
        int wantNative = (text[0] == '*');
        const char *displayText = wantNative ? text + 1 : text;

        /* Top-level menu bar item (level 0) */
        if (level == 0) {
            GtkWidget *item = gtk_menu_item_new_with_label(displayText);
            gtk_menu_shell_append(GTK_MENU_SHELL(menubar), item);
            GtkWidget *submenu = gtk_menu_new();
            gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), submenu);
            if (level + 1 < MAX_GTK_MENU_DEPTH)
                stack[level + 1] = submenu;
            continue;
        }

        /* Separator */
        if (strcmp(displayText, "-") == 0) {
            if (level < MAX_GTK_MENU_DEPTH && stack[level])
                gtk_menu_shell_append(GTK_MENU_SHELL(stack[level]),
                    gtk_separator_menu_item_new());
            continue;
        }

        GtkWidget *item = gtk_menu_item_new_with_label(displayText);

        if (wantNative) {
            /* Native-only: handle known items, else show dialog */
            if (strcmp(displayText, "Quit") == 0 ||
                strcmp(displayText, "Exit") == 0) {
                g_signal_connect(item, "activate",
                    G_CALLBACK(on_quit_activate), NULL);
            } else {
                g_signal_connect(item, "activate",
                    G_CALLBACK(on_no_native_handler),
                    (gpointer)displayText);
            }
        } else {
            /* No '*' — route to JavaScript */
            g_signal_connect(item, "activate",
                G_CALLBACK(on_menu_item_activate), (gpointer)displayText);
        }

        if (level < MAX_GTK_MENU_DEPTH && stack[level])
            gtk_menu_shell_append(GTK_MENU_SHELL(stack[level]), item);

        /* If next entry is deeper, this becomes a submenu parent */
        if (menu_template[i + 1].level > level) {
            GtkWidget *submenu = gtk_menu_new();
            gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), submenu);
            if (level + 1 < MAX_GTK_MENU_DEPTH)
                stack[level + 1] = submenu;
        }
    }
    #undef MAX_GTK_MENU_DEPTH

    return menubar;
}

/* ---- Quit when the window is closed ---- */
static void on_window_destroy(GtkWidget *widget, gpointer data)
{
    (void)widget; (void)data;
    gtk_main_quit();
}

/* ---- Self-install desktop integration (icon + .desktop file) ---- */
static gboolean g_installed_desktop = FALSE;
static gboolean g_installed_icon = FALSE;

static void linux_ensure_desktop_integration(void)
{
    if (linux_icon_png_len == 0) return;

    /* Resolve our own absolute path via /proc/self/exe */
    char exe_path[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (n <= 0) return;
    exe_path[n] = '\0';

    const char *home = g_get_home_dir();
    if (!home) return;

    /* ---- Install icon into hicolor theme if missing ---- */
    char *icon_dir = g_strdup_printf(
        "%s/.local/share/icons/hicolor/256x256/apps", home);
    g_mkdir_with_parents(icon_dir, 0755);

    char *icon_path = g_strdup_printf("%s/%s.png", icon_dir, MENU_PROGNAME);

    /* Write icon if missing or if size doesn't match (e.g. stale stub) */
    gboolean need_icon = TRUE;
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
        GStatBuf st;
        if (g_stat(icon_path, &st) == 0 &&
            (gsize)st.st_size == linux_icon_png_len)
            need_icon = FALSE;
    }
    if (need_icon) {
        g_file_set_contents(icon_path,
                            (const gchar *)linux_icon_png,
                            (gssize)linux_icon_png_len, NULL);
        /* Ask GTK to refresh the icon cache (best-effort) */
        char *cache_cmd = g_strdup_printf(
            "gtk-update-icon-cache -f -t '%s/.local/share/icons/hicolor'",
            home);
        g_spawn_command_line_async(cache_cmd, NULL);
        g_free(cache_cmd);
        g_installed_icon = TRUE;
    }
    g_free(icon_path);
    g_free(icon_dir);

    /* ---- Set file-manager icon on the binary itself (GIO metadata) ---- */
    {
        char *icon_uri = g_strdup_printf(
            "file://%s/.local/share/icons/hicolor/256x256/apps/%s.png",
            home, MENU_PROGNAME);
        GFile *exe_file = g_file_new_for_path(exe_path);
        GError *gio_err = NULL;
        gboolean ok = g_file_set_attribute_string(exe_file,
            "metadata::custom-icon", icon_uri,
            G_FILE_QUERY_INFO_NONE, NULL, &gio_err);
        if (!ok) {
            fprintf(stderr, "[passiflora] gio metadata::custom-icon failed: %s\n",
                    gio_err ? gio_err->message : "unknown");
            if (gio_err) g_error_free(gio_err);
        } else {
            fprintf(stderr, "[passiflora] gio metadata::custom-icon set to %s\n",
                    icon_uri);
            /* Touch parent directory so file managers notice the change */
            char *exe_dir = g_path_get_dirname(exe_path);
            GFile *dir_file = g_file_new_for_path(exe_dir);
            guint64 now = (guint64)(g_get_real_time() / 1000000) * 1000000;
            g_file_set_attribute_uint64(dir_file,
                G_FILE_ATTRIBUTE_TIME_MODIFIED, now / 1000000,
                G_FILE_QUERY_INFO_NONE, NULL, NULL);
            g_object_unref(dir_file);
            g_free(exe_dir);
        }
        g_object_unref(exe_file);
        g_free(icon_uri);
    }

    /* ---- Create or update .desktop file ---- */
    char *desktop_dir = g_strdup_printf(
        "%s/.local/share/applications", home);
    g_mkdir_with_parents(desktop_dir, 0755);

    char *desktop_path = g_strdup_printf(
        "%s/%s.desktop", desktop_dir, MENU_PROGNAME);
    g_free(desktop_dir);

    /* Read existing file (if any) to check whether Exec= is current */
    gboolean needs_write = TRUE;
    char *existing = NULL;
    if (g_file_get_contents(desktop_path, &existing, NULL, NULL)) {
        char *expected_exec = g_strdup_printf("Exec=%s\n", exe_path);
        if (strstr(existing, expected_exec))
            needs_write = FALSE;
        g_free(expected_exec);
        g_free(existing);
    }

    if (needs_write) {
        char *contents = g_strdup_printf(
                 "[Desktop Entry]\n"
                 "Type=Application\n"
                 "Name=%s\n"
                 "Exec=%s\n"
                 "Icon=%s\n"
                 "Terminal=false\n"
                 "Categories=Utility;\n"
                 "StartupWMClass=%s\n",
                 MENU_PROGNAME, exe_path, MENU_PROGNAME, MENU_PROGNAME);
        g_file_set_contents(desktop_path, contents, -1, NULL);
        g_free(contents);
        g_installed_desktop = TRUE;
    }
    g_free(desktop_path);
}

/* ---- Auto-grant geolocation permission ---- */
static gboolean on_permission_request(WebKitWebView *wv,
                                      WebKitPermissionRequest *request,
                                      gpointer data)
{
    (void)wv; (void)data;
    if (WEBKIT_IS_GEOLOCATION_PERMISSION_REQUEST(request)) {
        webkit_permission_request_allow(request);
        return TRUE;   /* handled */
    }
    return FALSE;      /* let WebKit deny other types */
}

/* ---- Native geolocation via GeoClue2 D-Bus ---- */

/* Data passed through the async GeoClue2 chain */
typedef struct {
    char        *callback_id;   /* JS callback id, e.g. "geo_1" */
    GDBusProxy  *client;        /* GeoClue2 Client proxy */
    gulong       sig_id;        /* "g-signal" handler id */
    guint        timeout_id;    /* GSource id for timeout */
} GeoRequest;

static void geo_request_finish(GeoRequest *gr)
{
    if (gr->timeout_id) { g_source_remove(gr->timeout_id); gr->timeout_id = 0; }
    if (gr->sig_id && gr->client)
        { g_signal_handler_disconnect(gr->client, gr->sig_id); gr->sig_id = 0; }
    if (gr->client) {
        g_dbus_proxy_call_sync(gr->client, "Stop", NULL,
            G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
        g_object_unref(gr->client);
        gr->client = NULL;
    }
    g_free(gr->callback_id);
    g_free(gr);
}

/* Called when GeoClue2 emits LocationUpdated(old_path, new_path) */
static void on_location_updated(GDBusProxy *proxy,
                                const gchar *sender_name,
                                const gchar *signal_name,
                                GVariant *parameters,
                                gpointer data)
{
    (void)proxy; (void)sender_name;
    GeoRequest *gr = data;

    if (strcmp(signal_name, "LocationUpdated") != 0) return;

    const char *old_path = NULL, *new_path = NULL;
    g_variant_get(parameters, "(&o&o)", &old_path, &new_path);
    (void)old_path;

    if (!new_path || strcmp(new_path, "/") == 0) return;

    /* Read properties from the Location object */
    GError *err = NULL;
    GDBusProxy *loc = g_dbus_proxy_new_for_bus_sync(
        G_BUS_TYPE_SYSTEM, G_DBUS_PROXY_FLAGS_NONE, NULL,
        "org.freedesktop.GeoClue2", new_path,
        "org.freedesktop.GeoClue2.Location",
        NULL, &err);

    if (!loc) {
        char js2[512];
        snprintf(js2, sizeof js2,
            "PassifloraIO._geoReject('%s', 2, 'Position unavailable');",
            gr->callback_id);
        if (g_linux_webview)
            webkit_web_view_evaluate_javascript(g_linux_webview, js2, -1,
                                                NULL, NULL, NULL, NULL, NULL);
        if (err) g_error_free(err);
        geo_request_finish(gr);
        return;
    }

    double lat = 0, lon = 0, accuracy = 0;
    GVariant *v;
    v = g_dbus_proxy_get_cached_property(loc, "Latitude");
    if (v) { lat = g_variant_get_double(v); g_variant_unref(v); }
    v = g_dbus_proxy_get_cached_property(loc, "Longitude");
    if (v) { lon = g_variant_get_double(v); g_variant_unref(v); }
    v = g_dbus_proxy_get_cached_property(loc, "Accuracy");
    if (v) { accuracy = g_variant_get_double(v); g_variant_unref(v); }

    char js[512];
    snprintf(js, sizeof js,
        "PassifloraIO._geoResolve('%s', %.8f, %.8f, %.2f);",
        gr->callback_id, lat, lon, accuracy);
    if (g_linux_webview)
        webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                            NULL, NULL, NULL, NULL, NULL);
    g_object_unref(loc);
    geo_request_finish(gr);
}

/* Timeout if GeoClue2 never delivers a location */
static gboolean on_geo_timeout(gpointer data)
{
    GeoRequest *gr = data;
    gr->timeout_id = 0;   /* source is auto-removed after firing */
    char js[512];
    snprintf(js, sizeof js,
        "PassifloraIO._geoReject('%s', 2, 'Position unavailable');",
        gr->callback_id);
    if (g_linux_webview)
        webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                            NULL, NULL, NULL, NULL, NULL);
    geo_request_finish(gr);
    return G_SOURCE_REMOVE;
}

/* GetClient callback — set up client, listen for LocationUpdated, Start */
static void on_geoclue_client_ready(GObject *source, GAsyncResult *res,
                                    gpointer data)
{
    GeoRequest *gr = data;
    GError *err = NULL;
    GVariant *result = g_dbus_proxy_call_finish(G_DBUS_PROXY(source),
                                                res, &err);
    if (!result || err) {
        char js[512];
        snprintf(js, sizeof js,
            "PassifloraIO._geoReject('%s', 2, 'Position unavailable');",
            gr->callback_id);
        if (g_linux_webview)
            webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                                NULL, NULL, NULL, NULL, NULL);
        if (err) g_error_free(err);
        geo_request_finish(gr);
        return;
    }

    const char *client_path = NULL;
    g_variant_get(result, "(&o)", &client_path);

    gr->client = g_dbus_proxy_new_for_bus_sync(
        G_BUS_TYPE_SYSTEM, G_DBUS_PROXY_FLAGS_NONE, NULL,
        "org.freedesktop.GeoClue2", client_path,
        "org.freedesktop.GeoClue2.Client",
        NULL, &err);
    g_variant_unref(result);

    if (!gr->client) {
        char js[512];
        snprintf(js, sizeof js,
            "PassifloraIO._geoReject('%s', 2, 'Position unavailable');",
            gr->callback_id);
        if (g_linux_webview)
            webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                                NULL, NULL, NULL, NULL, NULL);
        if (err) g_error_free(err);
        geo_request_finish(gr);
        return;
    }

    /* Set DesktopId */
    g_dbus_proxy_call_sync(gr->client,
        "org.freedesktop.DBus.Properties.Set",
        g_variant_new("(ssv)",
            "org.freedesktop.GeoClue2.Client", "DesktopId",
            g_variant_new_string(MENU_PROGNAME)),
        G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);

    /* Set accuracy level (EXACT = 8) */
    g_dbus_proxy_call_sync(gr->client,
        "org.freedesktop.DBus.Properties.Set",
        g_variant_new("(ssv)",
            "org.freedesktop.GeoClue2.Client", "RequestedAccuracyLevel",
            g_variant_new_uint32(8)),
        G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);

    /* Listen for LocationUpdated signal BEFORE calling Start */
    gr->sig_id = g_signal_connect(gr->client, "g-signal",
                                  G_CALLBACK(on_location_updated), gr);

    /* 5-second timeout */
    gr->timeout_id = g_timeout_add_seconds(5, on_geo_timeout, gr);

    /* Start the client — GeoClue2 will emit LocationUpdated when ready */
    g_dbus_proxy_call_sync(gr->client, "Start", NULL,
        G_DBUS_CALL_FLAGS_NONE, -1, NULL, &err);
    if (err) {
        char js[512];
        snprintf(js, sizeof js,
            "PassifloraIO._geoReject('%s', 2, 'Position unavailable');",
            gr->callback_id);
        if (g_linux_webview)
            webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                                NULL, NULL, NULL, NULL, NULL);
        g_error_free(err);
        geo_request_finish(gr);
        return;
    }
    /* Now we wait — on_location_updated or on_geo_timeout will fire */
}

/* ---- POSIX bridge via native message handler ---- */

/* Validate callback ID format (posix_N) to prevent JS injection */
static int is_valid_posix_id(const char *id)
{
    if (!id || strncmp(id, "posix_", 6) != 0) return 0;
    const char *p = id + 6;
    if (*p == '\0') return 0;
    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }
    return 1;
}

/* GLib thread function: run POSIX call and schedule JS callback */
typedef struct {
    char *params;
    char *cb_id;
} PosixTask;

static gboolean posix_result_idle(gpointer data)
{
    char **pair = (char **)data;    /* [0]=cb_id, [1]=json */
    if (g_linux_webview) {
        char *js = g_strdup_printf(
            "PassifloraIO._posixResolve('%s',%s);", pair[0], pair[1]);
        webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                            NULL, NULL, NULL, NULL, NULL);
        g_free(js);
    }
    free(pair[1]);   /* json from passiflora_posix_call */
    g_free(pair[0]); /* cb_id */
    g_free(pair);
    return G_SOURCE_REMOVE;
}

static gpointer posix_thread_func(gpointer data)
{
    PosixTask *task = (PosixTask *)data;
    extern char *passiflora_posix_call(const char *);
    char *json = passiflora_posix_call(task->params);
    char **pair = g_new(char *, 2);
    pair[0] = task->cb_id;       /* already g_strdup'd */
    pair[1] = json ? json : strdup("{}");
    g_idle_add(posix_result_idle, pair);
    g_free(task->params);
    g_free(task);
    return NULL;
}

static void on_posix_message(WebKitUserContentManager *manager,
                             WebKitJavascriptResult *js_result,
                             gpointer data)
{
    (void)manager; (void)data;
    JSCValue *val = webkit_javascript_result_get_js_value(js_result);
    char *params = jsc_value_to_string(val);
    if (!params) return;

    /* Extract id= from URL-encoded params */
    char *cb_id = NULL;
    char *p = params;
    while (*p) {
        if (strncmp(p, "id=", 3) == 0) {
            p += 3;
            const char *end = strchr(p, '&');
            size_t len = end ? (size_t)(end - p) : strlen(p);
            cb_id = g_strndup(p, len);
            break;
        }
        const char *amp = strchr(p, '&');
        if (!amp) break;
        p = (char *)amp + 1;
    }

    if (!cb_id || !is_valid_posix_id(cb_id)) {
        g_free(cb_id);
        g_free(params);
        return;
    }

    PosixTask *task = g_new(PosixTask, 1);
    task->params = params;    /* transfer ownership */
    task->cb_id = cb_id;
    g_thread_new("posix", posix_thread_func, task);
}

/* Validate callback ID format (geo_N) to prevent JS injection */
static int is_valid_geo_id(const char *id)
{
    if (!id || strncmp(id, "geo_", 4) != 0) return 0;
    const char *p = id + 4;
    if (*p == '\0') return 0;
    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }
    return 1;
}

/* JS sent passifloraGeolocation message — start GeoClue2 */
static void on_geolocation_message(WebKitUserContentManager *manager,
                                   WebKitJavascriptResult *js_result,
                                   gpointer data)
{
    (void)manager; (void)data;
    JSCValue *val = webkit_javascript_result_get_js_value(js_result);
    char *callback_id = jsc_value_to_string(val);

    if (!is_valid_geo_id(callback_id)) {
        g_free(callback_id);
        return;
    }

    GeoRequest *gr = g_new0(GeoRequest, 1);
    gr->callback_id = callback_id;

    GError *err = NULL;
    GDBusProxy *mgr = g_dbus_proxy_new_for_bus_sync(
        G_BUS_TYPE_SYSTEM, G_DBUS_PROXY_FLAGS_NONE, NULL,
        "org.freedesktop.GeoClue2",
        "/org/freedesktop/GeoClue2/Manager",
        "org.freedesktop.GeoClue2.Manager",
        NULL, &err);
    if (!mgr) {
        char js[512];
        snprintf(js, sizeof js,
            "PassifloraIO._geoReject('%s', 2, 'Position unavailable');",
            gr->callback_id);
        if (g_linux_webview)
            webkit_web_view_evaluate_javascript(g_linux_webview, js, -1,
                                                NULL, NULL, NULL, NULL, NULL);
        if (err) g_error_free(err);
        geo_request_finish(gr);
        return;
    }

    g_dbus_proxy_call(mgr, "GetClient", NULL,
        G_DBUS_CALL_FLAGS_NONE, -1, NULL,
        on_geoclue_client_ready, gr);
}

/* ---- Notify user about desktop setup once the page has loaded ---- */
static void on_page_loaded(WebKitWebView *wv, WebKitLoadEvent event,
                           gpointer data)
{
    (void)data;
    if (event != WEBKIT_LOAD_FINISHED) return;

    if (g_installed_desktop || g_installed_icon) {
        const char *msg = g_installed_desktop
            ? "alert('Program is new or has been moved. "
              ".desktop entry has been adjusted. "
              "You may need to navigate away in the file manager "
              "and back for the icon to appear.')"
            : "alert('App icon has been installed. "
              "You may need to navigate away in the file manager "
              "and back for the icon to appear.')";
        webkit_web_view_evaluate_javascript(wv,
            msg, -1, NULL, NULL, NULL, NULL, NULL);
        g_installed_desktop = FALSE;
        g_installed_icon = FALSE;
    }
}

/* ---- Entry point ---- */
void ui_open(int port)
{
    gtk_init(NULL, NULL);

    /* Set program name so GNOME can match WM_CLASS to .desktop file */
    g_set_prgname(MENU_PROGNAME);

    /* Install icon + .desktop file if needed (self-contained binary) */
    linux_ensure_desktop_integration();

    /* Main window */
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), MENU_PROGNAME);
    gtk_window_set_default_size(GTK_WINDOW(window), 1024, 768);

    /* Set window icon from embedded PNG */
    fprintf(stderr, "[passiflora] icon: embedded %u bytes, first byte 0x%02x\n",
            linux_icon_png_len,
            linux_icon_png_len > 0 ? linux_icon_png[0] : 0);
    if (linux_icon_png_len > 0) {
        GInputStream *stream = g_memory_input_stream_new_from_data(
            linux_icon_png, linux_icon_png_len, NULL);
        GError *perr = NULL;
        GdkPixbuf *icon = gdk_pixbuf_new_from_stream(stream, NULL, &perr);
        if (icon) {
            gtk_window_set_icon(GTK_WINDOW(window), icon);
            gtk_window_set_default_icon(icon);   /* dock / taskbar */
            g_object_unref(icon);
            fprintf(stderr, "[passiflora] icon: set successfully\n");
        } else {
            fprintf(stderr, "[passiflora] icon: pixbuf failed: %s\n",
                    perr ? perr->message : "unknown");
            if (perr) g_error_free(perr);
        }
        g_object_unref(stream);
    }

    g_signal_connect(window, "destroy",
                     G_CALLBACK(on_window_destroy), NULL);

    /* Vertical box: menu bar + web view */
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), vbox);

    /* Menu bar */
    GtkWidget *menubar = build_gtk_menus();
    gtk_box_pack_start(GTK_BOX(vbox), menubar, FALSE, FALSE, 0);

    /* WebKit web view with script message handler for geolocation */
    WebKitUserContentManager *ucm = webkit_user_content_manager_new();
    webkit_user_content_manager_register_script_message_handler(
        ucm, "passifloraGeolocation");
    g_signal_connect(ucm, "script-message-received::passifloraGeolocation",
                     G_CALLBACK(on_geolocation_message), NULL);
    webkit_user_content_manager_register_script_message_handler(
        ucm, "passifloraPosix");
    g_signal_connect(ucm, "script-message-received::passifloraPosix",
                     G_CALLBACK(on_posix_message), NULL);

    g_linux_webview = WEBKIT_WEB_VIEW(
        webkit_web_view_new_with_user_content_manager(ucm));
    g_signal_connect(g_linux_webview, "load-changed",
                     G_CALLBACK(on_page_loaded), NULL);
    g_signal_connect(g_linux_webview, "permission-request",
                     G_CALLBACK(on_permission_request), NULL);
    gtk_box_pack_start(GTK_BOX(vbox), GTK_WIDGET(g_linux_webview),
                       TRUE, TRUE, 0);

    /* Navigate to the local server */
    char url[256];
    snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
    webkit_web_view_load_uri(g_linux_webview, url);

    /* Show and run */
    gtk_widget_show_all(window);
    gtk_main();         /* blocks until quit */

    exit(0);
}

/* ================================================================== */
/*  Unsupported platform                                               */
/* ================================================================== */
#else

void ui_open(int port)
{
    (void)port;
    fprintf(stderr, "ui_open: unsupported platform\n");
}

#endif
