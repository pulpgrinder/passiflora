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

/* Generated menu data — MENU_PROGNAME */
#include "menu.c"

/* Port passed from main() to the app delegate via a global */
static int g_ios_port = 0;

/* ------------------------------------------------------------------ */
/*  Scene delegate (iOS 13+) — creates the window and web view         */
/* ------------------------------------------------------------------ */
@interface ZSSceneDelegate : UIResponder <UIWindowSceneDelegate, WKUIDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ZSSceneDelegate
- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)connectionOptions
{
    (void)session; (void)connectionOptions;
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    /* Full-screen WKWebView */
    WKWebViewConfiguration *config =
        [[WKWebViewConfiguration alloc] init];
    /* Allow inline media playback (no forced fullscreen) */
    config.allowsInlineMediaPlayback = YES;

    WKWebView *webView =
        [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    webView.UIDelegate = self;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = webView;

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    /* Navigate to the local server */
    NSString *urlStr =
        [NSString stringWithFormat:@"http://localhost:%d/", g_ios_port];
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

/* Generated menu data — menu_template[] and MENU_PROGNAME */
#include "menu.c"

/* Global WKWebView so the menu handler can call JavaScript */
static WKWebView *g_webView = nil;

/* ------------------------------------------------------------------ */
/*  Menu handler — calls handlemenu() in the embedded WKWebView        */
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
        @"if(typeof handlemenu==='function')handlemenu('%@')", title];
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
        NSString *title = [NSString stringWithUTF8String:text];

        /* Check for a known system item */
        SEL action = NULL;
        NSString *keyEq = @"";
        NSUInteger modMask = NSEventModifierFlagCommand;
        int isSystem = 0;

        for (int k = 0; known_items[k].prefix; k++) {
            const char *p = known_items[k].prefix;
            int exact = known_items[k].exact;
            BOOL match = exact
                ? [title isEqualToString:
                    [NSString stringWithUTF8String:p]]
                : [title hasPrefix:
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
            action = @selector(menuAction:);
            keyEq  = @"";
        }

        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:title
                   action:action
            keyEquivalent:keyEq];

        if (isSystem) {
            [item setKeyEquivalentModifierMask:modMask];
        } else {
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
    <NSApplicationDelegate, NSWindowDelegate, WKUIDelegate>
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
        g_webView =
            [[WKWebView alloc] initWithFrame:[[window contentView] bounds]
                               configuration:config];
        [g_webView setUIDelegate:delegate];
        [g_webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [window setContentView:g_webView];

        /* Navigate to the local server */
        NSString *urlStr =
            [NSString stringWithFormat:@"http://localhost:%d/", port];
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
#include "win_menu.c"

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
    void *_pad23;  /* add_PermissionRequested */
    void *_pad24;  /* remove_PermissionRequested */
    void *_pad25;  /* add_ProcessFailed */
    void *_pad26;  /* remove_ProcessFailed */
    void *_pad27;  /* AddScriptToExecuteOnDocumentCreated */
    void *_pad28;  /* RemoveScriptToExecuteOnDocumentCreated */
    HRESULT (STDMETHODCALLTYPE *ExecuteScript)(
        ICoreWebView2*,LPCWSTR,void*);    /* 29 */
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

        /* Top-level menu bar item (level 0) */
        if (level == 0) {
            HMENU popup = CreatePopupMenu();
            AppendMenuA(menubar, MF_POPUP, (UINT_PTR)popup, text);
            if (level + 1 < MAX_WIN_MENU_DEPTH)
                stack[level + 1] = popup;
            continue;
        }

        /* Separator */
        if (strcmp(text, "-") == 0) {
            if (level < MAX_WIN_MENU_DEPTH && stack[level])
                AppendMenuA(stack[level], MF_SEPARATOR, 0, NULL);
            continue;
        }

        /* Check if next entry is deeper => this becomes a submenu */
        if (menu_template[i + 1].level > level) {
            HMENU sub = CreatePopupMenu();
            if (level < MAX_WIN_MENU_DEPTH && stack[level])
                AppendMenuA(stack[level], MF_POPUP, (UINT_PTR)sub, text);
            if (level + 1 < MAX_WIN_MENU_DEPTH)
                stack[level + 1] = sub;
            continue;
        }

        /* Regular leaf item — assign a command ID */
        int idx = st->menuCount;
        if (idx < WIN_MENU_MAX_ITEMS) {
            st->menuTitles[idx] = text;
            st->menuCount++;
            if (level < MAX_WIN_MENU_DEPTH && stack[level])
                AppendMenuA(stack[level], MF_STRING,
                            WIN_MENU_ID_BASE + idx, text);
        }
    }
    #undef MAX_WIN_MENU_DEPTH
    return menubar;
}

/* ---- Call handlemenu() in the WebView ---- */
static void win_call_handlemenu(WV2State *st, const char *title)
{
    if (!st->webview) return;

    /* Build JS: if(typeof handlemenu==='function')handlemenu('...') */
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
        "if(typeof handlemenu==='function')handlemenu('%s')", escaped);

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
        if (idx >= 0 && idx < g_wv2.menuCount && g_wv2.menuTitles[idx])
            win_call_handlemenu(&g_wv2, g_wv2.menuTitles[idx]);
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
        snprintf(url, sizeof url, "http://localhost:%d/", port);
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
#include <webkit2/webkit2.h>
#include <string.h>

/* Generated menu data — MENU_PROGNAME, menu_template[] */
#include "menu.c"

static WebKitWebView *g_linux_webview = NULL;

/* ---- Call handlemenu() in the WebView ---- */
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
        "if(typeof handlemenu==='function')handlemenu('%s')", escaped);

    webkit_web_view_run_javascript(g_linux_webview, js,
                                   NULL, NULL, NULL);
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

        /* Top-level menu bar item (level 0) */
        if (level == 0) {
            GtkWidget *item = gtk_menu_item_new_with_label(text);
            gtk_menu_shell_append(GTK_MENU_SHELL(menubar), item);
            GtkWidget *submenu = gtk_menu_new();
            gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), submenu);
            if (level + 1 < MAX_GTK_MENU_DEPTH)
                stack[level + 1] = submenu;
            continue;
        }

        /* Separator */
        if (strcmp(text, "-") == 0) {
            if (level < MAX_GTK_MENU_DEPTH && stack[level])
                gtk_menu_shell_append(GTK_MENU_SHELL(stack[level]),
                    gtk_separator_menu_item_new());
            continue;
        }

        GtkWidget *item = gtk_menu_item_new_with_label(text);

        /* Known items: Quit/Exit close the application */
        if (strcmp(text, "Quit") == 0 || strcmp(text, "Exit") == 0) {
            g_signal_connect(item, "activate",
                G_CALLBACK(on_quit_activate), NULL);
        } else {
            g_signal_connect(item, "activate",
                G_CALLBACK(on_menu_item_activate), (gpointer)text);
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

/* ---- Entry point ---- */
void ui_open(int port)
{
    gtk_init(NULL, NULL);

    /* Main window */
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "");
    gtk_window_set_default_size(GTK_WINDOW(window), 1024, 768);
    g_signal_connect(window, "destroy",
                     G_CALLBACK(on_window_destroy), NULL);

    /* Vertical box: menu bar + web view */
    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(window), vbox);

    /* Menu bar */
    GtkWidget *menubar = build_gtk_menus();
    gtk_box_pack_start(GTK_BOX(vbox), menubar, FALSE, FALSE, 0);

    /* WebKit web view */
    g_linux_webview = WEBKIT_WEB_VIEW(webkit_web_view_new());
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
