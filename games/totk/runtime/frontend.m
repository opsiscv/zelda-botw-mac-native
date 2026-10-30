/* Native macOS window and VI service adapter. No guest frame is synthesized. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#include <stdatomic.h>
#include <math.h>
#include "runtime.h"
#include "game_version.h"
#include "totk_ui_lang.h"
#include "gamepad_layout.h"
#include "menu_pointer.h"
#include "menu_grid.h"
#include "space_skip.h"
#include "key_map.h"
#include "../third_party/d2r_gfx/gfx/nvn/totk_mfx_mode.h"
#include "../third_party/d2r_gfx/gfx/nvn/fps_overlay.h"
static NSWindow *window;
uint64_t dm_nvn_frame_count(void);   /* gfx/nvn/hle_nvn.c: game frames presented so far */
static CAMetalLayer *metalLayer;
static NSView *bootOverlay;
static NSTextField *bootStage,*bootDetail;
static NSProgressIndicator *bootProgress;
static NSView *hudBox;   /* the FPS / shader / load box (TOTKHudBox), nil with TOTK_HUD=corners */
/* The settings panel (key 1, settings_panel.h): while it is open the game gets no keyboard or mouse input. */
static int settingsOpen;
static void settings_show(int open);
/* Mouse mode (the settings panel, runtime/gamepad.m): while it is on and the window has the keyboard, the window holds the
   pointer -- moved to the window's centre, detached from the mouse and hidden -- and sends the mouse's buttons and
   movement to gamepad.m. It lets go when the window loses the keyboard (Command-Tab, a click elsewhere), during text
   entry, while the settings panel is open and when mouse mode goes off (front_mouse_update). */
static BOOL mouseHeld;
static int textEntryOpen;
static void front_mouse_update(void);
int taa_enabled(void);   /* third_party/d2r_gfx/gfx/nvn/totk_taa.m: edge smoothing in the settings panel */
void taa_set(int on);
static uint64_t bootStartNS;
static _Atomic uint64_t presentedFrames;
static _Atomic int warmPending;
static CVDisplayLinkRef displayLink;
static _Atomic int focused;
static pthread_mutex_t vsyncLock=PTHREAD_MUTEX_INITIALIZER;
static void *vsyncEvents[16];
static unsigned vsyncCount;
void hle_bind_system_event(void *,int);
void hle_signal_system_event(void *);
void *front_metal_layer(void){return (__bridge void *)metalLayer;}
void front_frame_presented(void){
 if(atomic_fetch_add_explicit(&presentedFrames,1,memory_order_relaxed)==0){
  fprintf(stderr,"[totk-boot] %.3f first presented frame\n",(runtime_now_ns()-bootStartNS)/1e9);
  dispatch_async(dispatch_get_main_queue(), ^{if(!atomic_load(&warmPending))bootOverlay.hidden=YES;});
 }
}
void runtime_boot_progress(const char *stage,uint64_t done,uint64_t total){
 static const char *last;
 if(stage!=last){fprintf(stderr,"[totk-boot] %.3f %s\n",bootStartNS?(runtime_now_ns()-bootStartNS)/1e9:0,stage?stage:"startup");last=stage;}
 NSString *s=[NSString stringWithUTF8String:stage?stage:TOTK_UI("正在启动","Starting")];
 dispatch_async(dispatch_get_main_queue(), ^{
  if(!bootOverlay||bootOverlay.hidden)return;
  bootStage.stringValue=s;
  if(total){bootDetail.stringValue=[NSString stringWithFormat:@"%.1f / %.1f GB",done/1e9,total/1e9];
   bootProgress.indeterminate=NO;bootProgress.doubleValue=(double)done/(double)total*100.0;}
  else {bootDetail.stringValue=@(TOTK_UI("正在处理，请稍候","Working, please wait"));bootProgress.indeterminate=YES;[bootProgress startAnimation:nil];}
 });
}
void runtime_boot_count(const char *stage,uint64_t done,uint64_t total){
 /* Steps counted in items, not bytes (the shader import: tens of thousands of files, minutes on a phone). */
 static const char *last;
 if(stage!=last){fprintf(stderr,"[totk-boot] %.3f %s\n",bootStartNS?(runtime_now_ns()-bootStartNS)/1e9:0,stage?stage:"startup");last=stage;}
 NSString *s=[NSString stringWithUTF8String:stage?stage:TOTK_UI("正在启动","Starting")];
 dispatch_async(dispatch_get_main_queue(), ^{
  if(!bootOverlay||bootOverlay.hidden)return;
  bootStage.stringValue=s;bootDetail.stringValue=[NSString stringWithFormat:@"%llu / %llu",(unsigned long long)done,(unsigned long long)total];
  if(total){bootProgress.indeterminate=NO;bootProgress.doubleValue=(double)done/(double)total*100.0;}
 });
}
void runtime_boot_status(const char *stage,const char *detail){
 if(bootStartNS)fprintf(stderr,"[totk-boot] %.3f %s — %s\n",(runtime_now_ns()-bootStartNS)/1e9,stage?stage:"startup",detail?detail:"");
 NSString *s=[NSString stringWithUTF8String:stage?stage:TOTK_UI("正在启动","Starting")];
 NSString *d=[NSString stringWithUTF8String:detail?detail:TOTK_UI("正在处理，请稍候","Working, please wait")];
 dispatch_async(dispatch_get_main_queue(), ^{
  if(!bootOverlay||bootOverlay.hidden)return;
  bootStage.stringValue=s;bootDetail.stringValue=d;
  bootProgress.indeterminate=YES;[bootProgress startAnimation:nil];
 });
}
void runtime_warm_progress(uint64_t done,uint64_t total,uint64_t shaders,uint64_t shader_total,uint64_t pipelines,uint64_t pipeline_total){
 atomic_store(&warmPending,1);
 dispatch_async(dispatch_get_main_queue(), ^{
  if(!bootOverlay||bootOverlay.hidden)return;
  double percent=total ? fmin(100.0,(double)done/(double)total*100.0) : 100.0;
  bootStage.stringValue=[NSString stringWithFormat:@(TOTK_UI("预热着色器与管线 %.0f%%","Warming shaders and pipelines %.0f%%")),floor(percent)];
  bootDetail.stringValue=[NSString stringWithFormat:@(TOTK_UI("着色器 %llu/%llu · 管线 %llu/%llu","shaders %llu/%llu · pipelines %llu/%llu")),
      (unsigned long long)shaders,(unsigned long long)shader_total,
      (unsigned long long)pipelines,(unsigned long long)pipeline_total];
  bootProgress.indeterminate=NO;
  bootProgress.doubleValue=percent;
 });
}
void runtime_warm_done(void){
 atomic_store(&warmPending,0);
 dispatch_async(dispatch_get_main_queue(), ^{if(atomic_load(&presentedFrames))bootOverlay.hidden=YES;});
}
uint64_t front_game_res(int docked){(void)docked;return (720ULL<<32)|1280;}
/* TOTK_ASSUME_FOCUS=1: unattended test runs. macOS refuses to activate an app launched from the background while the user is working in
   another one; the window then never becomes key, GetCurrentFocusState stays 0 and the game waits before its first frame. In this mode the
   game is told it is focused, and the window is shown without taking the keyboard from the user (scripted input does not need it). */
static int assume_focus(void){static int v=-1;if(v<0){const char *e=getenv("TOTK_ASSUME_FOCUS");v=e&&atoi(e);}return v;}
/* Keep the guest active when the macOS window loses key status. Native input is still cleared
   in windowDidResignKey so a held key cannot remain stuck while another app has focus. */
int runtime_front_focus(void){return 1;}
static CVReturn vsync_callback(CVDisplayLinkRef link,const CVTimeStamp *now,const CVTimeStamp *output,CVOptionFlags flags,CVOptionFlags *out,void *ctx){
 (void)link;(void)now;(void)output;(void)flags;(void)out;(void)ctx;
 pthread_mutex_lock(&vsyncLock);for(unsigned i=0;i<vsyncCount;i++)hle_signal_system_event(vsyncEvents[i]);pthread_mutex_unlock(&vsyncLock);return kCVReturnSuccess;
}
@interface TOTKInputView:NSView
@property(strong) NSTimer *cursorHideTimer;
@property BOOL cursorAutoHideActive;
@property BOOL cursorIsHidden;
-(void)setCursorAutoHideEnabled:(BOOL)enabled;
@end
/* The pointer hidden or shown, from one place (NSCursor hide / unhide must pair: extra ones left it shown on the world, 2026-10-29). */
static BOOL cursorHiddenNow;
static void set_cursor_hidden(BOOL h){if(h==cursorHiddenNow)return;cursorHiddenNow=h;if(h)[NSCursor hide];else [NSCursor unhide];
 if(getenv("TOTK_DEBUG_LOG"))fprintf(stderr,"[totk] pointer %s\n",h?"hidden":"shown");}
@implementation TOTKInputView
-(BOOL)acceptsFirstResponder{return YES;}
/* While the settings panel is open only key 1 (it closes the panel, runtime/input.c) and Esc (closes it here, not the game's
   menu) do anything; releases still go through so nothing stays held. */
/* Esc in a menu (the world stopped) is B, back, and Enter and Space are A; in the world they stay what they map to. In a
   menu E and Shift do nothing (user 2026-10-29: only Enter and Space confirm, only Esc goes back), E being the next tab
   in the inventory and the Adventure Log. Kept per press. */
extern int runtime_game_world_live(void) __attribute__((weak));
extern int runtime_inventory_slots(MenuSlot *,int,int *) __attribute__((weak));
extern int runtime_quest_log_live(void) __attribute__((weak));
/* The pause menu's inventory or Adventure Log is open (the System tab has no sign here: from it Q goes back). */
extern int runtime_inventory_live(void) __attribute__((weak));   /* game_patches_botw.c: the pause menu's inventory step runs */
static int pause_tabs_open(void){return (runtime_quest_log_live&&runtime_quest_log_live())||(runtime_inventory_live&&runtime_inventory_live());}
static unsigned escAs,enterAs,eAs,spaceAs,vAs;
/* The one state of the mouse in menus (title_tick decides it every 8 ms; user 2026-10-29: as simple as that):
   uiMenu   a menu's items are on screen (runtime_ui_hits): the pointer is shown and is the selection;
   mouseHeld the mouse turns the camera (the world playing, no menu): the pointer hidden where it is, never moved;
   keysLead a key walked the menu: the game's own selection until the mouse moves again. */
static int uiMenu,keysLead;
extern int runtime_ui_hits(MenuHit *,int,int *) __attribute__((weak));extern void runtime_ui_select(uint64_t) __attribute__((weak));
extern void runtime_ui_mouse_rules(int) __attribute__((weak));   /* game_patches_botw.c */
static int in_menu(void){return runtime_game_world_live&&!runtime_game_world_live();}
enum{KEY_NONE=255,KEY_SKIP=254};   /* runtime_input_key ignores them; KEY_SKIP: J (A) and I (X) together */
static int world_on(void){return !runtime_game_world_live||runtime_game_world_live();}
static unsigned space_key(void){int r=space_role(world_on(),0,uiMenu);return r==SPACE_SKIP?KEY_SKIP:r==SPACE_CONFIRM?38:49;}
/* A window key after the settings panel: what it presses depends on where the game is (above). */
static unsigned horseE,horseShift;   /* on horseback (user 2026-10-29): Shift spurs (A), E gets off (B); kept per press */
static int riding(void){extern int runtime_horse_state(float *,float *) __attribute__((weak));float y,v;return runtime_horse_state&&runtime_horse_state(&y,&v);}
static void front_key_down(unsigned short code,int repeat){
 if(code==14&&(repeat?horseE:riding())){if(!repeat)horseE=56;runtime_input_key(56,1);return;}
 if(code==56&&(repeat?horseShift:riding())){if(!repeat)horseShift=38;runtime_input_key(38,1);return;}
 if(code!=53&&code!=48&&code!=12&&code!=14&&code!=36&&code!=49&&!(code>=18&&code<=29))keysLead=1;   /* a key that walks the menu (not Esc, Tab, Q, E, Enter, Space, digits) */
 if(code==56&&in_menu())return;   /* Shift in a menu: nothing (only Esc goes back) */
 if(code==53){if(!repeat)escAs=esc_is_plus(world_on(),0,uiMenu)?53:56;runtime_input_key(escAs,1);return;}   /* a menu: back; else + */
 if(code==14){if(!repeat)eAs=pause_tabs_open()?59:in_menu()?KEY_NONE:14;runtime_input_key(eAs,1);return;}   /* E in the pause menu: the next tab (R, Control), as Q (L) the one before; A in the world */
 if(code==9){if(!repeat)vAs=pause_tabs_open()?32:9;runtime_input_key(vAs,1);return;}   /* V in the inventory: sort (Y, U; the left click is A there); the d-pad's down elsewhere */
 if(code==49){if(!repeat){spaceAs=space_key();fprintf(stderr,"[totk-input] Space: %s\n",spaceAs==KEY_SKIP?"A and X (cutscene, dialog)":spaceAs==38?"A (menu)":"X (world)");}if(spaceAs==KEY_SKIP){runtime_input_key(38,1);runtime_input_key(34,1);}else runtime_input_key(spaceAs,1);return;}   /* space_skip.h */
 if(code==36){if(!repeat)enterAs=runtime_game_world_live&&!runtime_game_world_live()?38:36;runtime_input_key(enterAs,1);return;}   /* Enter in a menu: A */
 runtime_input_key(code,1);}
static void front_key_up(unsigned short code){if(code==14&&horseE){runtime_input_key(horseE,0);horseE=0;return;}if(code==56&&horseShift){runtime_input_key(horseShift,0);horseShift=0;return;}if(code==53&&escAs){runtime_input_key(escAs,0);escAs=0;return;}if(code==36&&enterAs){runtime_input_key(enterAs,0);enterAs=0;return;}if(code==14&&eAs){runtime_input_key(eAs,0);eAs=0;return;}if(code==9&&vAs){runtime_input_key(vAs,0);vAs=0;return;}if(code==49&&spaceAs){if(spaceAs==KEY_SKIP){runtime_input_key(38,0);runtime_input_key(34,0);}else runtime_input_key(spaceAs,0);spaceAs=0;return;}runtime_input_key(code,0);}
/* keys.txt next to controls.txt (TOTK_CONTROLS; key_map.h): read at the first key. A bad line is logged and the
   default kept. */
static unsigned key_remap(unsigned code){static uint8_t map[KEY_MAP_SIZE];static int loaded;
 if(!loaded){loaded=1;key_map_default(map);const char *c=getenv("TOTK_CONTROLS"),*slash=c?strrchr(c,'/'):NULL;
  if(slash){char path[4096],text[16384];snprintf(path,sizeof path,"%.*s/keys.txt",(int)(slash-c),c);FILE *f=fopen(path,"rb");
   if(f){size_t n=fread(text,1,sizeof text-1,f);fclose(f);text[n]=0;const char *error=NULL;int line=key_map_parse(text,map,&error);
    if(line)fprintf(stderr,"[totk-input] %s line %d: %s; the default keys are used\n",path,line,error);
    else{int moved=0;for(int i=0;i<KEY_MAP_SIZE;i++)moved+=map[i]!=i;fprintf(stderr,"[totk-input] keys: %s (%d keys moved)\n",path,moved);}}}}
 return code<KEY_MAP_SIZE?map[code]:code;}
static void mapped_key(unsigned code,int down,int repeat){unsigned c=key_remap(code);if(c==KEY_MAP_NONE)return;if(down)front_key_down((unsigned short)c,repeat);else front_key_up((unsigned short)c);}
/* input.txt "winkey <code> <ms>": a key as the window would get it, through front_key_down (runtime/input.c). */
void runtime_front_key(unsigned code,unsigned ms){dispatch_async(dispatch_get_main_queue(),^{front_key_down((unsigned short)code,0);});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)ms*NSEC_PER_MSEC),dispatch_get_main_queue(),^{front_key_up((unsigned short)code);});}
-(void)keyDown:(NSEvent *)e{if(settingsOpen&&e.keyCode!=18){if(e.keyCode==53)settings_show(0);return;}mapped_key(e.keyCode,1,e.isARepeat);}
-(void)keyUp:(NSEvent *)e{mapped_key(e.keyCode,0,0);}
/* Caps Lock (ZL) pressed and released, read from the keyboards themselves: macOS's key events report only its lock state.
   Needs Input Monitoring (asked once); without it, flagsChanged falls back to the lock state. */
static int capsHid;
static void caps_hid_value(void *ctx,IOReturn r,void *sender,IOHIDValueRef v){(void)ctx;(void)r;(void)sender;
 IOHIDElementRef el=IOHIDValueGetElement(v);if(IOHIDElementGetUsagePage(el)!=kHIDPage_KeyboardOrKeypad||IOHIDElementGetUsage(el)!=kHIDUsage_KeyboardCapsLock)return;
 int down=IOHIDValueGetIntegerValue(v)!=0;if(!NSApp.isActive&&down)return;if(!settingsOpen||!down)mapped_key(57,down,0);}
static void caps_hid_start(void){
 if(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)!=kIOHIDAccessTypeGranted&&!IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)){fprintf(stderr,"[totk-input] Caps Lock: no Input Monitoring permission, it works as a lock (ZL held while on)\n");return;}
 IOHIDManagerRef m=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
 IOHIDManagerSetDeviceMatching(m,(__bridge CFDictionaryRef)@{@kIOHIDDeviceUsagePageKey:@(kHIDPage_GenericDesktop),@kIOHIDDeviceUsageKey:@(kHIDUsage_GD_Keyboard)});
 IOHIDManagerRegisterInputValueCallback(m,caps_hid_value,NULL);
 IOHIDManagerScheduleWithRunLoop(m,CFRunLoopGetMain(),kCFRunLoopDefaultMode);
 if(IOHIDManagerOpen(m,kIOHIDOptionsTypeNone)!=kIOReturnSuccess){fprintf(stderr,"[totk-input] Caps Lock: keyboards not readable, it works as a lock\n");return;}
 capsHid=1;fprintf(stderr,"[totk-input] Caps Lock: held and released like any key (ZL)\n");}
/* Caps Lock (ZL): without capsHid macOS reports only its lock state, so the shield stays up while the lock is on. */
-(void)flagsChanged:(NSEvent *)e{NSEventModifierFlags f=e.modifierFlags;unsigned k=e.keyCode;
 int down=k==56?!!(f&NSEventModifierFlagShift):k==58?!!(f&NSEventModifierFlagOption):k==59?!!(f&NSEventModifierFlagControl):k==57&&!capsHid?!!(f&NSEventModifierFlagCapsLock):-1;
 if(down>=0&&(!settingsOpen||!down))mapped_key(k,down,0);}
/* The game has no mouse controls. With mouse mode off, in native full screen, the pointer is kept out of the picture while
   idle and shown again as soon as it moves; with mouse mode on, title_tick alone shows or hides it. */
void runtime_input_key_synthetic(unsigned code,int down);
static unsigned clickKey;   /* a synthetic press, let go at the next tick */
static void press(unsigned code){if(clickKey)return;clickKey=code;runtime_input_key_synthetic(code,1);}
static NSCursor *menuCursor;   /* the menus' pointer: cursor.png next to controls.txt, else the arrow */
static NSCursor *menu_cursor(void){if(!menuCursor){char path[4096];extern int runtime_setting_path(const char *,char *,size_t);
  NSImage *im=runtime_setting_path("cursor.png",path,sizeof path)?[[NSImage alloc] initWithContentsOfFile:@(path)]:nil;
  if(im){im.size=NSMakeSize(24,24*im.size.height/fmax(1,im.size.width));menuCursor=[[NSCursor alloc] initWithImage:im hotSpot:NSMakePoint(1,1)];}else menuCursor=NSCursor.arrowCursor;}
 return menuCursor;}
-(void)resetCursorRects{if(uiMenu)[self addCursorRect:self.bounds cursor:menu_cursor()];else [super resetCursorRects];}   /* kept by AppKit over the window */
-(void)hideCursorIfIdle:(NSTimer *)timer{
 (void)timer;self.cursorHideTimer=nil;
 if(runtime_mouse_enabled()||!self.cursorAutoHideActive||!self.window.isKeyWindow||!(self.window.styleMask&NSWindowStyleMaskFullScreen))return;
 set_cursor_hidden(YES);
}
-(void)mouseMoved:(NSEvent *)e{
 if(mouseHeld){runtime_mouse_move(e.deltaX,e.deltaY);return;}
 keysLead=0;   /* the mouse has the say again */
 if(uiMenu)[menu_cursor() set];
 if(runtime_mouse_enabled()||!self.cursorAutoHideActive)return;
 [self.cursorHideTimer invalidate];set_cursor_hidden(NO);
 self.cursorHideTimer=[NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(hideCursorIfIdle:) userInfo:nil repeats:NO];
}
static void menu_scroll(int steps);
-(void)scrollWheel:(NSEvent *)e{   /* by notches (menu_wheel): a notch of the wheel is one step */
 static MenuWheel wheel;if(e.momentumPhase!=NSEventPhaseNone)return;
 int steps=menu_wheel(&wheel,e.timestamp,e.deltaY);if(!steps)return;
 extern int runtime_input_dpad_held(void);   /* a quick-select bar (weapons, runes, shields, bows, arrows): the wheel walks it */
 if(mouseHeld||runtime_input_dpad_held()){extern void runtime_mouse_wheel(int);runtime_mouse_wheel(steps);}else menu_scroll(steps);}
-(void)mouseDragged:(NSEvent *)e{if(mouseHeld)runtime_mouse_move(e.deltaX,e.deltaY);}
-(void)rightMouseDragged:(NSEvent *)e{if(mouseHeld)runtime_mouse_move(e.deltaX,e.deltaY);}
-(void)otherMouseDragged:(NSEvent *)e{if(mouseHeld)runtime_mouse_move(e.deltaX,e.deltaY);}
static void menu_click(void);
-(void)mouseDown:(NSEvent *)e{(void)e;if(mouseHeld)runtime_mouse_button(0,1);else if(runtime_mouse_enabled())menu_click();}
-(void)mouseUp:(NSEvent *)e{(void)e;runtime_mouse_button(0,0);}
-(void)rightMouseDown:(NSEvent *)e{(void)e;if(mouseHeld)runtime_mouse_button(1,1);else if(runtime_mouse_enabled())press(56);}   /* off the camera: B */   /* no context menu */
-(void)rightMouseUp:(NSEvent *)e{(void)e;runtime_mouse_button(1,0);}
-(void)otherMouseDown:(NSEvent *)e{if(mouseHeld)runtime_mouse_button((int)e.buttonNumber,1);}   /* 2 middle, 3 and 4 the side buttons */
-(void)otherMouseUp:(NSEvent *)e{runtime_mouse_button((int)e.buttonNumber,0);}
-(void)setCursorAutoHideEnabled:(BOOL)enabled{
 self.cursorAutoHideActive=enabled;
 [self.cursorHideTimer invalidate];self.cursorHideTimer=nil;
 if(enabled){
  self.window.acceptsMouseMovedEvents=YES;
  self.cursorHideTimer=[NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(hideCursorIfIdle:) userInfo:nil repeats:NO];
 }else if(!runtime_mouse_enabled())set_cursor_hidden(NO);
}
@end
static NSPoint fakePointer;static int fakePointerOn;   /* tests: "pointer <x> <y>" (layout units) stands for the mouse */
static NSPoint menu_pointer_view(NSView *v){return fakePointerOn?fakePointer:[v convertPoint:v.window.mouseLocationOutsideOfEventStream fromView:nil];}
static void pointer_layout(double *lx,double *ly){   /* the pointer in layout units (1280x720 shown aspect-fit, centre 0,0, y up) */
 NSView *v=window.contentView;NSPoint p=menu_pointer_view(v);double w=v.bounds.size.width,h=v.bounds.size.height,sc=fmin(w/1280,h/720);
 *lx=(p.x-(w-1280*sc)/2)/sc-640;*ly=(p.y-(h-720*sc)/2)/sc-360;}
void runtime_menu_pointer(double lx,double ly){dispatch_async(dispatch_get_main_queue(),^{
 NSSize z=window.contentView.bounds.size;double s=fmin(z.width/1280,z.height/720);
 fakePointer=NSMakePoint((z.width-1280*s)/2+(lx+640)*s,(z.height-720*s)/2+(ly+360)*s);fakePointerOn=1;keysLead=0;});}
void runtime_menu_wheel(int n){dispatch_async(dispatch_get_main_queue(),^{menu_scroll(n);});}   /* tests: "wheel <notches>" */
static MenuHit uiHits[MENU_SLOTS_MAX];static int uiN,uiInventory;   /* this tick's boxes (title_tick) */
static int menu_target(void){double lx,ly;pointer_layout(&lx,&ly);return menu_hit_at(uiHits,uiN,lx,ly);}
static int walkDir;static uint64_t walkId,walkUntil;   /* a grid's page turn by its edge (menu_scroll, title_tick) */
static void menu_scroll(int steps){   /* the wheel moves no selection (user 2026-10-29): a grid's pages only, the Adventure Log's list scrolled */
 extern void runtime_inventory_page(int);extern void runtime_list_scroll(int);
 if(uiMenu&&runtime_quest_log_live&&runtime_quest_log_live()){runtime_list_scroll(steps);return;}
 if(!uiMenu||!uiInventory)return;
 if(runtime_inventory_live&&runtime_inventory_live()){runtime_inventory_page(steps);return;}   /* the pause menu: the game's own page turn */
 /* another grid (a shop's): its edge item that way selected, then one d-pad step past it turns the page */
 double lx,ly;pointer_layout(&lx,&ly);int best=-1;
 for(int i=0;i<uiN;i++){if(best<0){best=i;continue;}
  double dx=steps>0?uiHits[i].x-uiHits[best].x:uiHits[best].x-uiHits[i].x;
  if(dx>2||(fabs(dx)<=2&&fabs(uiHits[i].y-ly)<fabs(uiHits[best].y-ly)))best=i;}
 if(best<0||!runtime_ui_select)return;
 walkDir=steps>0?1:-1;walkId=uiHits[best].id;walkUntil=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)+400000000ull;runtime_ui_select(walkId);}
static void menu_click(void){   /* the left button off the camera: A on the item under the pointer; beside the inventory's
 page its page turn; off the items nothing; where there are no items (a dialog, a cutscene) A */
 if(!uiMenu){press(38);return;}
 if(menu_target()>=0){press(38);return;}
 double lx,ly;pointer_layout(&lx,&ly);extern void runtime_inventory_page(int);
 if(uiInventory&&(lx<MENU_GRID_PAGE_LEFT_X||lx>MENU_GRID_PAGE_RIGHT_X)&&fabs(ly)<260)runtime_inventory_page(lx<MENU_GRID_PAGE_LEFT_X?-1:1);}
static void title_tick(void){   /* main thread, every 8 ms: the three answers, nothing else */
 if(clickKey){runtime_input_key_synthetic(clickKey,0);clickKey=0;}
 int on=runtime_mouse_enabled()&&!settingsOpen;
 int hsel=-1;uiN=on&&runtime_ui_hits?runtime_ui_hits(uiHits,MENU_SLOTS_MAX,&hsel):0;
 uint64_t selId=hsel>=0?uiHits[hsel].id:0;
 int inv=0;for(int i=0;i<uiN;i++)inv+=fabsf(uiHits[i].w-90)<6&&fabsf(uiHits[i].h-90)<6;uiInventory=inv>=2;   /* its 90 x 90 slots */
 if(uiInventory&&runtime_inventory_live&&runtime_inventory_live()){int k=0;for(int i=0;i<uiN;i++)if(uiHits[i].x>=MENU_GRID_PAGE_LEFT_X-10&&uiHits[i].x<=MENU_GRID_PAGE_RIGHT_X+10)uiHits[k++]=uiHits[i];uiN=k;}   /* its page only */
 extern int runtime_input_dpad_held(void);int menu=uiN>0&&!runtime_input_dpad_held();   /* the quick-select bar is no menu (the camera's) */
 if(menu!=uiMenu){uiMenu=menu;fprintf(stderr,"[totk] menu pointer: %s\n",menu?"a menu":"no menu");
  [window invalidateCursorRectsForView:window.contentView];if(menu){[menu_cursor() set];window.acceptsMouseMovedEvents=YES;}}
 front_mouse_update();
 if(on&&window.isKeyWindow)set_cursor_hidden(mouseHeld||(!menu&&NSPointInRect(NSEvent.mouseLocation,[window convertRectToScreen:window.contentView.frame])));   /* shown only on a menu; off the game's window it is the Mac's */
 if(runtime_ui_mouse_rules)runtime_ui_mouse_rules(on&&!keysLead);
 if(walkDir){if(selId==walkId){press(walkDir>0?11:3);walkDir=0;return;}   /* there: the step past the edge (B right, F left) */
  if(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)>walkUntil)walkDir=0;else return;}
 if(!menu||keysLead||!runtime_ui_select)return;
 static uint64_t sent=1;int t=menu_target();uint64_t want=t>=0?uiHits[t].id:0;   /* the item under the pointer, or none */
 if(want!=sent||want!=selId){sent=want;runtime_ui_select(want);}   /* asked again until the game shows it (a page turning refuses a moment) */
}
static void front_mouse_update(void){   /* main thread: the mouse on the camera only in the world, with the pointer on the game */
 BOOL want=window&&runtime_mouse_enabled()&&window.isKeyWindow&&!textEntryOpen&&!settingsOpen&&!uiMenu&&world_on();
 if(want&&!mouseHeld&&!NSPointInRect(NSEvent.mouseLocation,[window convertRectToScreen:window.contentView.frame]))want=NO;   /* another screen: not taken */
 if(want==mouseHeld)return;
 mouseHeld=want;
 if(want){CGAssociateMouseAndMouseCursorPosition(false);set_cursor_hidden(YES);window.acceptsMouseMovedEvents=YES;}   /* the pointer stays where it is, hidden */
 else{CGAssociateMouseAndMouseCursorPosition(true);set_cursor_hidden(NO);runtime_mouse_release();}   /* and shows there again, never moved */
 fprintf(stderr,"[totk] mouse %s\n",want?"held by the window (the settings panel, key 1, or Command-Tab lets it go)":"let go");
}
/* Debug: the menu's hit boxes drawn over the picture (TOTK_HITBOXES=1, or input.txt "hitboxes 1"): each element's box
   as runtime_ui_hits reads it, in the layout's units (1280x720, centre 0,0) put on the view as the pointer is; green,
   the selected one red, the one under the pointer filled. Lets every menu be checked: a box that is not on its item. */
@interface TOTKHitBoxes:NSView
@property(strong) NSTimer *timer;
@end
static TOTKHitBoxes *hitBoxes;
@implementation TOTKHitBoxes{MenuHit hits[MENU_SLOTS_MAX];int n,sel,under;}
-(NSView *)hitTest:(NSPoint)p{(void)p;return nil;}   /* clicks go through */
-(void)drawRect:(NSRect)r{(void)r;
 NSSize z=self.bounds.size;double sc=fmin(z.width/1280,z.height/720),ox=(z.width-1280*sc)/2,oy=(z.height-720*sc)/2;
 for(int i=0;i<n;i++){NSRect b=NSMakeRect(ox+(hits[i].x-hits[i].w/2+640)*sc,oy+(hits[i].y-hits[i].h/2+360)*sc,hits[i].w*sc,hits[i].h*sc);
  NSColor *c=i==sel?NSColor.systemRedColor:NSColor.systemGreenColor;
  if(i==under){[[c colorWithAlphaComponent:0.25] setFill];NSRectFillUsingOperation(b,NSCompositingOperationSourceOver);}
  [c setStroke];NSBezierPath *p=[NSBezierPath bezierPathWithRect:b];p.lineWidth=1.5;[p stroke];}}
-(void)refresh{
 
 n=runtime_ui_hits&&uiMenu?runtime_ui_hits(hits,MENU_SLOTS_MAX,&sel):0;under=-1;
 if(n){NSPoint p=menu_pointer_view(self);NSSize z=self.bounds.size;double sc=fmin(z.width/1280,z.height/720);
  under=menu_hit_at(hits,n,(p.x-(z.width-1280*sc)/2)/sc-640,(p.y-(z.height-720*sc)/2)/sc-360);}
 [self setNeedsDisplay:YES];}
@end
void runtime_hitboxes(int on){dispatch_async(dispatch_get_main_queue(),^{
 if(on&&!hitBoxes){hitBoxes=[[TOTKHitBoxes alloc] initWithFrame:window.contentView.bounds];hitBoxes.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  [window.contentView addSubview:hitBoxes];__weak TOTKHitBoxes *w=hitBoxes;hitBoxes.timer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){(void)t;[w refresh];}];}
 else if(!on&&hitBoxes){[hitBoxes.timer invalidate];[hitBoxes removeFromSuperview];hitBoxes=nil;}
 fprintf(stderr,"[totk] hit boxes %s\n",on?"shown":"hidden");});}
@interface TOTKHudBox:NSView
@property(strong) NSTextField *label;
@property(strong) NSTimer *timer;
@property NSSize textSize;
-(void)position;
-(void)refresh;
@end
/* Compact HUD (default): one small box in the window's top-right corner with the FPS, shader and load lines (published by
   gfx/nvn/fps_overlay.c, refreshed twice a second); the settings panel's overlay row picks all, FPS only or none.
   TOTK_HUD=corners: the lines stay in the picture's corners and there is no box. */
@implementation TOTKHudBox
-(instancetype)initWithFrame:(NSRect)frame{if((self=[super initWithFrame:frame])){self.wantsLayer=YES;self.layer.backgroundColor=[NSColor colorWithCalibratedWhite:0.04 alpha:0.72].CGColor;self.layer.cornerRadius=7;self.layer.borderWidth=1;self.layer.borderColor=[NSColor colorWithCalibratedWhite:1 alpha:0.14].CGColor;
 self.label=[NSTextField labelWithString:@""];self.label.alignment=NSTextAlignmentLeft;self.label.maximumNumberOfLines=0;self.label.lineBreakMode=NSLineBreakByClipping;[self addSubview:self.label];
 [self refresh];__weak TOTKHudBox *weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){(void)t;[weak refresh];}];}return self;}
-(void)refresh{
 self.hidden=fps_overlay_hud_mode()==HUD_MODE_OFF;if(self.hidden)return;
 NSFont *mono=[NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightMedium];
 NSColor *green=[NSColor colorWithCalibratedRed:80/255.0 green:1 blue:120/255.0 alpha:1],*yellow=[NSColor colorWithCalibratedRed:1 green:230/255.0 blue:40/255.0 alpha:1];
 NSMutableAttributedString *a=[NSMutableAttributedString new];
 int full=fps_overlay_full_hud();   // FPS only: the FPS line (line 0); the others keep their last text, so skip them
 for(int i=0;i<4;i++){char t[128];int hl=0;if((!full&&i!=0)||!hud_snapshot(i,t,sizeof t,&hl))continue;   // FPS, shaders, render pipelines, load
  [a appendAttributedString:[[NSAttributedString alloc] initWithString:[([NSString stringWithUTF8String:t] ?: @"") stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName:mono,NSForegroundColorAttributeName:hl?yellow:green}]];}
 if(!a.length)[a appendAttributedString:[[NSAttributedString alloc] initWithString:@"FPS --\n" attributes:@{NSFontAttributeName:mono,NSForegroundColorAttributeName:green}]];
 /* The commit the app was built from (user 2026-10-25), last and grey: TOTK_SOURCE_COMMIT from the launcher. */
 const char *commit=getenv("TOTK_SOURCE_COMMIT");
 if(commit&&*commit)[a appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@(TOTK_UI("版本 %s\n","build %s\n")),commit]
  attributes:@{NSFontAttributeName:mono,NSForegroundColorAttributeName:[NSColor colorWithCalibratedWhite:0.6 alpha:1]}]];
 [a deleteCharactersInRange:NSMakeRange(a.length-1,1)];   // no empty line under the last one
 if([a isEqualToAttributedString:self.label.attributedStringValue])return;
 self.label.attributedStringValue=a;NSSize z=[self.label sizeThatFits:NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX)];self.textSize=NSMakeSize(ceil(z.width),ceil(z.height));[self position];}
-(NSView *)hitTest:(NSPoint)p{(void)p;return nil;}
-(void)viewDidMoveToSuperview{[super viewDidMoveToSuperview];[self position];}
-(void)layout{[super layout];[self position];}
-(void)position{if(!self.superview)return;
 CGFloat w=self.textSize.width+16,h=self.textSize.height+10,m=10;NSRect f=NSMakeRect(floor(self.superview.bounds.size.width-w-m),floor(self.superview.bounds.size.height-h-m),w,h);
 if(!NSEqualRects(self.frame,f))self.frame=f;self.label.frame=NSMakeRect(8,5,self.textSize.width,self.textSize.height);}
@end
#include "settings_panel.h"
/* The live FPS in the menu bar: a menu of the game's own, after its app menu on the left, whose title is the frame rate
   ("60 FPS", "50+50 FPS" while frame interpolation shows generated frames), refreshed twice a second with the value the
   overlay uses. Part of the app's own menu bar, so macOS shows it whenever the game is in front (a status item next to
   the clock can be hidden by System Settings > Menu Bar). Independent of key 1; hidden in full screen with the menu bar.
   TOTK_MENUBAR_FPS=0 leaves the menu bar alone. */
extern int dm_gfx_fps_now(int *generated) __attribute__((weak_import));   // gfx/nvn/nvn_mtl.m (absent in tests)
static NSMenu *fpsMenu;static NSMenuItem *fpsMenuItem;static NSTimer *fpsTimer;
static int menubar_fps_enabled(void){const char *e=getenv("TOTK_MENUBAR_FPS");return !(e&&!strcmp(e,"0"));}
static void front_menubar_fps_add(NSMenu *bar){   // from front_install_menu
 if(!menubar_fps_enabled())return;
 fpsMenu=[[NSMenu alloc] initWithTitle:@"FPS --"];
 NSMenuItem *about=[[NSMenuItem alloc] initWithTitle:@(TOTK_UI("实时帧率（TOTK_MENUBAR_FPS=0 可隐藏）","Live frame rate (TOTK_MENUBAR_FPS=0 hides it)")) action:nil keyEquivalent:@""];
 about.enabled=NO;[fpsMenu addItem:about];fpsMenu.autoenablesItems=NO;
 const char *commit=getenv("TOTK_SOURCE_COMMIT");   /* the commit the app was built from (build_app.py, the launcher) */
 if(commit&&*commit){NSMenuItem *build=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@(TOTK_UI("版本 %s","Build %s")),commit] action:nil keyEquivalent:@""];build.enabled=NO;[fpsMenu addItem:build];}
 fpsMenuItem=[[NSMenuItem alloc] initWithTitle:@"FPS --" action:nil keyEquivalent:@""];fpsMenuItem.submenu=fpsMenu;[bar addItem:fpsMenuItem];
}
/* TOTK_TITLE_FPS=1: the window title also ends in the frame rate ("Tears of the Kingdom  Mac — Ver. 1.4.3 — 60 FPS"),
   kept after whatever title the game set. Off by default: the menu bar already shows it. */
static int title_fps_enabled(void){const char *e=getenv("TOTK_TITLE_FPS");return e&&!strcmp(e,"1");}
static NSString *titleBase,*titleShown;
static void front_title_fps(NSString *fps){
 if(!title_fps_enabled()||!window)return;
 NSString *now=window.title;
 if(!titleShown||![now isEqualToString:titleShown])titleBase=now;   // the game changed its title: keep that one as the base
 titleShown=[NSString stringWithFormat:@"%@ — %@",titleBase,fps];
 if(![now isEqualToString:titleShown])window.title=titleShown;
}
static void front_menubar_fps(void){   // starts the refresh once the window exists
 if((!fpsMenu&&!title_fps_enabled())||fpsTimer)return;
 fpsTimer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){(void)t;
  int gen=0,fps=dm_gfx_fps_now?dm_gfx_fps_now(&gen):-1;
  NSString *title=fps<0?@"FPS --":gen>0?[NSString stringWithFormat:@"%d+%d FPS",fps,gen]:[NSString stringWithFormat:@"%d FPS",fps];
  if(fpsMenu&&![fpsMenu.title isEqualToString:title]){fpsMenu.title=title;fpsMenuItem.title=title;}
  front_title_fps(title);}];
}
/* The drawable follows the window's pixel size; the present pass scales the game picture (1920x1080 docked) into it and
   keeps 16:9 (black bars on other shapes), so a larger window or full screen shows the game at its own resolution instead
   of a fixed small drawable that the compositor stretches. */
/* TOTK_DRAWABLE_SCALE=<f> (test scripts only): the drawable is that many times the window's pixels and the window server
   scales it down for the screen. It lets a test exercise the 2K output path (a 2560x1440 picture) on a screen smaller than
   that (2026-10-17: the Mac reported a 1920x1080 display); the desktop launcher never sets it. */
static CGFloat drawable_scale(void){static CGFloat f=-1;if(f<0){const char *e=getenv("TOTK_DRAWABLE_SCALE");f=e?atof(e):1;if(f<0.25||f>4)f=1;}return f;}
static void front_sync_drawable(void){
 NSView *v=window.contentView;if(!v||!metalLayer)return;
 CGFloat s=window.backingScaleFactor>0?window.backingScaleFactor:1,ts=drawable_scale();CGSize px=CGSizeMake(round(v.bounds.size.width*s*ts),round(v.bounds.size.height*s*ts));
 if(px.width<1||px.height<1||CGSizeEqualToSize(metalLayer.drawableSize,px))return;
 metalLayer.contentsScale=s;metalLayer.drawableSize=px;fprintf(stderr,"[totk] window drawable %.0fx%.0f (scale %.0f)\n",px.width,px.height,s);runtime_aspect_view(px.width,px.height);
}
/* BotW, the settings panel's aspect ratio: the window takes the selected camera ratio. Keep the chosen height across toggles, even when a wide
   window has to shrink to fit the display; a manual resize establishes a new height. AppKit stays on the main queue. */
void runtime_front_resize_aspect(double ratio){
 if(!isfinite(ratio)||ratio<0.5||ratio>8)return;
 dispatch_async(dispatch_get_main_queue(), ^{
  if(!window||(window.styleMask&NSWindowStyleMaskFullScreen))return;
  NSScreen *screen=window.screen?:NSScreen.mainScreen;if(!screen)return;
  static NSSize lastSize;static CGFloat preferredHeight;
  NSRect oldFrame=window.frame;NSSize current=window.contentView.bounds.size;
  if(preferredHeight<=0||fabs(current.width-lastSize.width)>1||fabs(current.height-lastSize.height)>1)preferredHeight=current.height;
  NSRect visible=screen.visibleFrame;
  NSRect content=[window contentRectForFrameRect:visible];
  CGFloat h=fmin(preferredHeight,fmin(content.size.height,content.size.width/ratio));
  if(h<=0)return;
  NSRect frame=[window frameRectForContentRect:NSMakeRect(0,0,round(h*ratio),round(h))];
  frame.origin=NSMakePoint(NSMidX(oldFrame)-frame.size.width/2,NSMidY(oldFrame)-frame.size.height/2);
  frame.origin.x=fmax(NSMinX(visible),fmin(frame.origin.x,NSMaxX(visible)-frame.size.width));
  frame.origin.y=fmax(NSMinY(visible),fmin(frame.origin.y,NSMaxY(visible)-frame.size.height));
  [window setFrame:frame display:YES];
  lastSize=window.contentView.bounds.size;
  front_sync_drawable();
 });
}
@interface TOTKWindowDelegate:NSObject<NSWindowDelegate>
@end
@implementation TOTKWindowDelegate
-(void)windowDidBecomeKey:(NSNotification *)n{(void)n;atomic_store(&focused,1);if(window.styleMask&NSWindowStyleMaskFullScreen)[(TOTKInputView *)window.contentView setCursorAutoHideEnabled:YES];runtime_oe_push_message(15);front_mouse_update();fprintf(stderr,"[totk] window gained focus\n");}
-(void)windowDidResignKey:(NSNotification *)n{(void)n;atomic_store(&focused,0);[(TOTKInputView *)window.contentView setCursorAutoHideEnabled:NO];front_mouse_update();runtime_input_clear();runtime_oe_push_message(15);fprintf(stderr,"[totk] window lost focus\n");}
/* The process ends with the window. Save writes go straight to the files (runtime/fs_host.c), so a close in the middle of a
   save waits (up to 15 s, the window already gone) until the game has written and committed it (runtime_fs_save_busy). */
-(void)windowWillClose:(NSNotification *)n{(void)n;
 [(TOTKInputView *)window.contentView setCursorAutoHideEnabled:NO];
 if(mouseHeld){mouseHeld=NO;CGAssociateMouseAndMouseCursorPosition(true);set_cursor_hidden(NO);}
 if(!runtime_fs_save_busy()){fprintf(stderr,"[totk] window closed; graceful guest shutdown pending\n");_exit(0);}
 fprintf(stderr,"[totk] window closed while the game is saving: quitting when the save is done\n");
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  uint64_t t0=runtime_now_ns();while(runtime_fs_save_busy()&&runtime_now_ns()-t0<15000000000ull)usleep(20000);
  fprintf(stderr,"[totk] save %s after %.2f s; quitting\n",runtime_fs_save_busy()?"still in progress (gave up)":"done",(runtime_now_ns()-t0)/1e9);_exit(0);});
}
-(void)windowDidResize:(NSNotification *)n{(void)n;front_sync_drawable();}
-(void)windowDidEnterFullScreen:(NSNotification *)n{(void)n;[(TOTKInputView *)window.contentView setCursorAutoHideEnabled:window.isKeyWindow];}
-(void)windowDidExitFullScreen:(NSNotification *)n{(void)n;[(TOTKInputView *)window.contentView setCursorAutoHideEnabled:NO];}
/* Whether any part of the window can be seen (TOTK, 2026-10-16 night): macOS stops the display link's callbacks for a
   fully covered window, so presents stop and per-picture measurements of that stretch are void; a test session's log
   says when (the user working in other apps covered the test windows of the frame interpolation tests). */
static _Atomic int windowVisible=-1;   /* -1 not known yet; read by the present path's stall lines (runtime_front_window_visible) */
static void note_occlusion(const char *when){int v=(window.occlusionState&NSWindowOcclusionStateVisible)!=0;atomic_store(&windowVisible,v);
 fprintf(stderr,"[totk] window %s%s (frame %llu)\n",v?"visible":"covered (or on another Space): no presents until it is visible again",when,(unsigned long long)dm_nvn_frame_count());}
-(void)windowDidChangeOcclusionState:(NSNotification *)n{(void)n;note_occlusion("");}
-(void)windowDidChangeBackingProperties:(NSNotification *)n{(void)n;front_sync_drawable();}
@end
static TOTKWindowDelegate *windowDelegate;
int runtime_front_window_visible(void){return atomic_load(&windowVisible);}
void runtime_front_request_close(void){dispatch_async(dispatch_get_main_queue(), ^{[window performClose:nil];});}
/* Use the window-close path, not terminate:, so Command-Q also waits for active saves. */
static void front_install_menu(void){
 NSMenu *menu=[NSMenu new],*appMenu=[NSMenu new];
 NSMenuItem *appItem=[NSMenuItem new];appItem.submenu=appMenu;[menu addItem:appItem];
 NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@(TOTK_UI("退出 " GAME_NAME,"Quit " GAME_NAME)) action:@selector(performClose:) keyEquivalent:@"q"];
 quit.keyEquivalentModifierMask=NSEventModifierFlagCommand;quit.target=window;
 [appMenu addItem:quit];front_menubar_fps_add(menu);NSApp.mainMenu=menu;
}
static void *guest_main(void *callback){@autoreleasepool{((void(*)(void))callback)();}return NULL;}
void runtime_front_run(void(*callback)(void)){
 @autoreleasepool{
  bootStartNS=runtime_now_ns();
  {const char *commit=getenv("TOTK_SOURCE_COMMIT");fprintf(stderr,"[totk] built from commit %s\n",commit&&*commit?commit:"(not recorded)");}
  [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  runtime_mouse_set_hook(front_mouse_update);
  runtime_gamepad_start();
  /* Default window: the docked output size, 1920x1080, scaled down (16:9 kept) when the screen's visible area is smaller. */
  /* TOTK_WINDOW_SIZE=<w>x<h> (test scripts only, e.g. the 2K output test; the desktop launcher never sets it): another starting size. */
  NSRect vis=NSScreen.mainScreen?NSScreen.mainScreen.visibleFrame:NSMakeRect(0,0,1920,1080+28);CGFloat ww=1920,wh=1080;
  {const char *e=getenv("TOTK_WINDOW_SIZE");int w=0,h=0;if(e&&sscanf(e,"%dx%d",&w,&h)==2&&w>=320&&h>=180&&w<=8192&&h<=8192){ww=w;wh=h;}}
  CGFloat k=fmin(1,fmin(vis.size.width/ww,(vis.size.height-28)/wh));ww=floor(ww*k);wh=floor(wh*k);
  window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,ww,wh) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed=NO;   /* a close that waits for a save (windowWillClose) must not free the window the static pointer still holds */
  /* An agent's test game (TOTK_SLOT_OWNER other than user) says so in its title: it plays a save copy and its script closes it. */
  const char *owner=getenv("TOTK_SLOT_OWNER"),*purpose=getenv("TOTK_SLOT_PURPOSE");
  window.title=owner&&*owner&&strcmp(owner,"user")?[NSString stringWithFormat:@(TOTK_UI("测试局（%s）Ver. %s：%s — 存档副本，进度不会存进你的存档，脚本会自己关闭","Test session (%s) Ver. %s: %s — save copy, progress is not saved to your save, the script closes it")),owner,TOTK_GAME_VERSION,purpose&&*purpose?purpose:TOTK_UI("代理测试","agent test")]:[NSString stringWithFormat:@GAME_NAME "  Mac — Ver. %s",TOTK_GAME_VERSION];
  windowDelegate=[TOTKWindowDelegate new];window.delegate=windowDelegate;
  front_install_menu();
  window.collectionBehavior|=NSWindowCollectionBehaviorFullScreenPrimary;
  window.contentView=[[TOTKInputView alloc] initWithFrame:NSMakeRect(0,0,ww,wh)];
  metalLayer=[CAMetalLayer layer];metalLayer.device=MTLCreateSystemDefaultDevice();metalLayer.pixelFormat=MTLPixelFormatBGRA8Unorm;metalLayer.drawableSize=CGSizeMake(ww,wh);runtime_aspect_view(ww,wh);
  metalLayer.framebufferOnly=NO;window.contentView.wantsLayer=YES;window.contentView.layer=metalLayer;
  bootOverlay=[[NSView alloc] initWithFrame:window.contentView.bounds];bootOverlay.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  bootOverlay.wantsLayer=YES;bootOverlay.layer.backgroundColor=[NSColor colorWithCalibratedRed:0.035 green:0.075 blue:0.09 alpha:1].CGColor;
  bootStage=[NSTextField labelWithString:@(TOTK_UI("正在启动海拉鲁","Starting Hyrule"))];
  bootStage.font=[NSFont systemFontOfSize:25 weight:NSFontWeightSemibold];bootStage.textColor=NSColor.whiteColor;
  bootStage.alignment=NSTextAlignmentCenter;bootStage.frame=NSMakeRect(0,wh/2+20,ww,40);bootStage.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin|NSViewMaxYMargin;
  bootDetail=[NSTextField labelWithString:@(TOTK_UI("正在准备游戏环境","Preparing the game environment"))];
  bootDetail.font=[NSFont systemFontOfSize:14];bootDetail.textColor=[NSColor colorWithCalibratedWhite:0.72 alpha:1];
  bootDetail.alignment=NSTextAlignmentCenter;bootDetail.frame=NSMakeRect(0,wh/2-20,ww,28);bootDetail.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin|NSViewMaxYMargin;
  bootProgress=[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(ww/2-140,wh/2-55,280,10)];
  bootProgress.minValue=0;bootProgress.maxValue=100;bootProgress.indeterminate=YES;bootProgress.autoresizingMask=NSViewMinXMargin|NSViewMaxXMargin|NSViewMinYMargin|NSViewMaxYMargin;
  [bootOverlay addSubview:bootStage];[bootOverlay addSubview:bootDetail];[bootOverlay addSubview:bootProgress];
  [window.contentView addSubview:bootOverlay];[bootProgress startAnimation:nil];
  front_menubar_fps();caps_hid_start();
  [NSTimer scheduledTimerWithTimeInterval:0.008 repeats:YES block:^(NSTimer *t){(void)t;title_tick();}];
  /* The FPS, shader and load lines: in the corner box (compact HUD), or with TOTK_HUD=corners drawn into the game picture's
     corners by the present encoder (gfx/nvn/fps_overlay.c). The box sits under the opaque boot overlay until it is hidden. */
  if(hud_compact()){TOTKHudBox *box=[[TOTKHudBox alloc] initWithFrame:NSZeroRect];box.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;
   [window.contentView addSubview:box positioned:NSWindowBelow relativeTo:bootOverlay];[box position];hudBox=box;}
  if(getenv("TOTK_HITBOXES")&&atoi(getenv("TOTK_HITBOXES")))runtime_hitboxes(1);
  [window makeFirstResponder:window.contentView];[window center];front_sync_drawable();
  if(assume_focus()){[window orderFrontRegardless];}else{[window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];}   /* in front of other apps' windows, keyboard left alone */
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{note_occlusion(" 3 s after opening");});
  atomic_store(&focused,1);
  if(CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)||CVDisplayLinkSetOutputCallback(displayLink,vsync_callback,NULL)||CVDisplayLinkStart(displayLink))runtime_fail("native display link initialization");
  pthread_t guest;pthread_attr_t attr;pthread_attr_init(&attr);pthread_attr_setstacksize(&attr,8*1024*1024);int err=pthread_create(&guest,&attr,guest_main,(void *)callback);pthread_attr_destroy(&attr);if(err)runtime_fail("native game thread creation");
  [NSApp run];runtime_fail("native event loop returned unexpectedly");
 }
}
/* Text entry for the game (nn::swkbd::ShowKeyboard, runtime/swkbd_host.c; on the Switch a keyboard applet takes the screen).
   User, 2026-10-17: no on-screen keyboard, just the Mac keyboard. A bar at the bottom of the game window shows the game's
   prompt and one text field (input methods work); Return confirms, Escape cancels. Characters the game disallows and text
   beyond its length limit are removed as they are typed (the caller checks again). The calling guest thread waits on a
   semaphore; the game's keys are cleared while the bar has the keyboard. */
@interface TOTKTextBar:NSView<NSTextFieldDelegate>
@property(strong) NSTextField *field;
@property int maxUnits,minUnits,digitsOnly;
@property uint32_t disabled;
@property(copy) void(^done)(NSString *text);   /* nil: cancelled */
-(void)refilter;
@end
@implementation TOTKTextBar
-(BOOL)allowed:(unichar)c{
 BOOL digit=c>='0'&&c<='9';uint32_t d=self.disabled;
 if(self.digitsOnly&&!digit)return NO;
 if(c<0x20||c==0x7f)return NO;
 if((d&1u<<1&&c==' ')||(d&1u<<2&&c=='@')||(d&1u<<3&&c=='%')||(d&1u<<4&&c=='/')||(d&1u<<5&&c=='\\')||(d&1u<<6&&digit))return NO;
 return YES;
}
-(void)controlTextDidChange:(NSNotification *)n{(void)n;[self refilter];}
-(void)refilter{
 NSText *ed=self.field.currentEditor;if([ed isKindOfClass:NSTextView.class]&&((NSTextView *)ed).hasMarkedText)return;   /* still composing */
 NSString *s=self.field.stringValue;NSMutableString *t=[NSMutableString string];
 [s enumerateSubstringsInRange:NSMakeRange(0,s.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *sub,NSRange r,NSRange er,BOOL *stop){
  (void)r;(void)er;
  if(sub.length==1&&![self allowed:[sub characterAtIndex:0]])return;
  if(self.maxUnits>0&&t.length+sub.length>(NSUInteger)self.maxUnits){*stop=YES;return;}
  [t appendString:sub];}];
 if(![t isEqualToString:s]){self.field.stringValue=t;NSBeep();}
}
-(void)finish:(NSString *)text{void(^d)(NSString *)=self.done;self.done=nil;if(d)d(text);}
-(BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel{
 (void)c;(void)tv;
 if(sel==@selector(insertNewline:)){[self refilter];NSString *s=self.field.stringValue;
  if((NSInteger)s.length<self.minUnits||!s.length){NSBeep();return YES;}[self finish:s];return YES;}
 if(sel==@selector(cancelOperation:)){[self finish:nil];return YES;}
 return NO;
}
@end
static __weak TOTKTextBar *openBar;   /* main thread only */
void runtime_front_text_test(const char *op,const char *text){
 NSString *o=[NSString stringWithUTF8String:op],*t=[NSString stringWithUTF8String:text?text:""]?:@"";
 dispatch_async(dispatch_get_main_queue(), ^{
  TOTKTextBar *bar=openBar;if(!bar){fprintf(stderr,"[totk] keyboard test: no text entry bar is open\n");return;}
  if([o isEqualToString:@"type"]){bar.field.stringValue=[bar.field.stringValue stringByAppendingString:t];[bar refilter];}
  else if([o isEqualToString:@"enter"])[bar control:bar.field textView:(NSTextView *)bar.field.currentEditor doCommandBySelector:@selector(insertNewline:)];
  else if([o isEqualToString:@"shot"]){   /* the bar as drawn (window screenshots of the game picture do not include AppKit views) */
   NSBitmapImageRep *rep=[bar bitmapImageRepForCachingDisplayInRect:bar.bounds];[bar cacheDisplayInRect:bar.bounds toBitmapImageRep:rep];
   NSData *png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];BOOL ok=[png writeToFile:t atomically:YES];
   fprintf(stderr,"[totk] keyboard test: bar picture %s %s\n",t.UTF8String,ok?"written":"FAILED");return;}
  else if([o isEqualToString:@"esc"])[bar control:bar.field textView:(NSTextView *)bar.field.currentEditor doCommandBySelector:@selector(cancelOperation:)];
  fprintf(stderr,"[totk] keyboard test: %s -> field \"%s\"\n",o.UTF8String,bar.field.stringValue.UTF8String);
 });
}
int runtime_front_text_input(const RuntimeTextRequest *req,char *out,size_t out_size){
 if(!window||!req||!out||!out_size){fprintf(stderr,"[totk] keyboard: no game window for text entry; cancelled\n");return 0;}
 NSString *prompt=[NSString stringWithUTF8String:req->prompt?req->prompt:""]?:@"",*initial=[NSString stringWithUTF8String:req->initial?req->initial:""]?:@"";
 int maxU=req->max_units,minU=req->min_units,digits=req->digits_only,secure=req->secure;uint32_t dis=req->disabled;
 __block NSString *result=nil;dispatch_semaphore_t sem=dispatch_semaphore_create(0);
 dispatch_async(dispatch_get_main_queue(), ^{
  NSView *cv=window.contentView;CGFloat w=fmin(720,cv.bounds.size.width-40),h=104;
  TOTKTextBar *bar=[[TOTKTextBar alloc] initWithFrame:NSMakeRect(floor((cv.bounds.size.width-w)/2),48,w,h)];
  bar.autoresizingMask=NSViewMinXMargin|NSViewMaxXMargin|NSViewMaxYMargin;bar.wantsLayer=YES;bar.layer.cornerRadius=12;
  bar.layer.backgroundColor=[NSColor colorWithCalibratedRed:0.035 green:0.075 blue:0.09 alpha:0.92].CGColor;
  bar.maxUnits=maxU;bar.minUnits=minU;bar.digitsOnly=digits;bar.disabled=dis;
  NSTextField *label=[NSTextField labelWithString:prompt];label.font=[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  label.textColor=NSColor.whiteColor;label.frame=NSMakeRect(18,h-36,w-36,22);label.lineBreakMode=NSLineBreakByTruncatingTail;
  NSString *limit=maxU>0?[NSString stringWithFormat:@(TOTK_UI("最多 %d 个字 · ","Up to %d characters · ")),maxU]:@"";
  NSTextField *hint=[NSTextField labelWithString:[NSString stringWithFormat:@(TOTK_UI("%@用键盘输入，回车确定，Esc 取消","%@Type with the keyboard, Return to confirm, Esc to cancel")),limit]];
  hint.font=[NSFont systemFontOfSize:12];hint.textColor=[NSColor colorWithCalibratedWhite:0.72 alpha:1];hint.alignment=NSTextAlignmentRight;
  hint.frame=NSMakeRect(18,h-36,w-36,20);hint.autoresizingMask=NSViewWidthSizable;
  NSTextField *field=secure?[[NSSecureTextField alloc] initWithFrame:NSMakeRect(18,16,w-36,34)]:[[NSTextField alloc] initWithFrame:NSMakeRect(18,16,w-36,34)];
  field.font=[NSFont systemFontOfSize:20];field.stringValue=initial;field.delegate=bar;field.bezelStyle=NSTextFieldRoundedBezel;bar.field=field;
  __weak TOTKTextBar *weakBar=bar;
  bar.done=^(NSString *text){result=[text copy];[weakBar removeFromSuperview];[window makeFirstResponder:window.contentView];textEntryOpen=0;front_mouse_update();dispatch_semaphore_signal(sem);};
  [bar addSubview:label];[bar addSubview:hint];[bar addSubview:field];[cv addSubview:bar];openBar=bar;
  runtime_input_clear();
  if(window.miniaturized)[window deminiaturize:nil];
  if(!assume_focus()){[NSApp activateIgnoringOtherApps:YES];[window makeKeyAndOrderFront:nil];}   /* test windows never take the keyboard */
  [window makeFirstResponder:field];
  textEntryOpen=1;front_mouse_update();   /* the pointer is the player's while typing */
  fprintf(stderr,"[totk] keyboard: text entry bar shown (%s)\n",prompt.UTF8String);
 });
 dispatch_semaphore_wait(sem,DISPATCH_TIME_FOREVER);
 if(!result)return 0;
 snprintf(out,out_size,"%s",result.UTF8String?result.UTF8String:"");
 return 1;
}
static int viReady;
static unsigned displayIdentity,layerIdentity;
static void vi_initialize(void){if(!metalLayer)runtime_fail("VI requires native macOS window");viReady=1;fprintf(stderr,"[totk] native VI display initialized\n");}
static uint32_t vi_open(void **out){if(!viReady||!out)return 0xf601;*out=&displayIdentity;return 0;}
static uint32_t vi_layer(void **out,void *display){if(!out||display!=&displayIdentity)return 0xf601;*out=&layerIdentity;return 0;}
static uint32_t vi_window(void **out,void *layer){if(!out||layer!=&layerIdentity)return 0xf601;*out=front_metal_layer();return 0;}
static uint32_t vi_vsync(void *ev,void *display){
 if(!ev||display!=&displayIdentity)return 0xf601;hle_bind_system_event(ev,1);
 pthread_mutex_lock(&vsyncLock);if(vsyncCount>=16)runtime_fail("VI display event limit");vsyncEvents[vsyncCount++]=ev;pthread_mutex_unlock(&vsyncLock);return 0;
}
#ifdef GAME_BOTW
static uint32_t vi_scaling_mode(void *layer,int mode){(void)layer;(void)mode;return 0;}
#endif
void *runtime_front_override(const char *name){
 static const struct{const char *name;void *fn;} entries[]={
 {"_ZN2nn2vi10InitializeEv",vi_initialize},{"_ZN2nn2vi18OpenDefaultDisplayEPPNS0_7DisplayE",vi_open},
 {"_ZN2nn2vi11CreateLayerEPPNS0_5LayerEPNS0_7DisplayE",vi_layer},{"_ZN2nn2vi15GetNativeWindowEPPvPNS0_5LayerE",vi_window},
 {"_ZN2nn2vi20GetDisplayVsyncEventEPNS_2os15SystemEventTypeEPNS0_7DisplayE",vi_vsync}
#ifdef GAME_BOTW
 ,{"_ZN2nn2vi19SetLayerScalingModeEPNS0_5LayerENS0_11ScalingModeE",vi_scaling_mode}   /* SDK 7: the window scales itself */
#endif
 };
 for(unsigned i=0;i<sizeof(entries)/sizeof(*entries);i++)if(!strcmp(name,entries[i].name))return entries[i].fn;return NULL;
}
