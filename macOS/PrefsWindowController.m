//
//  PrefsWindowController.m
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 1/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#import "PrefsWindowController.h"
#import <AR6/ARVideo/video.h>
#import "../calib_camera.h"

@interface PrefsWindowController ()

@end

@implementation PrefsWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName
{
    return [super initWithWindowNibName:windowNibName];
}

- (id)initWithWindow:(NSWindow *)window
{
    id ret;
    if ((ret = [super initWithWindow:window])) {
        // Customisation here.
    }
    return (ret);
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Pre-process, selecting options etc.
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    // Populate the camera input popup.
    ARVideoSourceInfoListT *sil = ar2VideoCreateSourceInfoList("-module=AVFoundation");
    if (!sil) {
        ARLOGe("Unable to get ARVideoSourceInfoListT.\n");
        cameraInputPopup.enabled = FALSE;
    } else {
        NSMutableArray *names = [NSMutableArray arrayWithCapacity:sil->count];
        for (int i = 0; i < sil->count; i++) {
            [names addObject:[NSString stringWithCString:sil->info[i].name encoding:NSUTF8StringEncoding]];
        }
        [cameraInputPopup addItemsWithTitles:names];
        [cameraInputPopup selectItemAtIndex:MIN([defaults integerForKey:@"cameraDeviceNumber"], sil->count - 1)];
        cameraInputPopup.enabled = TRUE;
    }
    
    NSString *cs = [defaults stringForKey:@"calibrationServerDNSNameOrIPAddress"];
    calibrationServerDNSNameOrIPAddress.stringValue = (cs ? cs : @"");
    
    showPrefsOnStartup.state = [defaults boolForKey:@"showPrefsOnStartup"];
}

- (BOOL)windowShouldClose:(id)sender
{
    return (YES);
}

- (void)windowWillClose:(NSNotification *)notification
{
    // Post-process selected options.
}

- (IBAction)okSelected:(NSButton *)sender {
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:cameraInputPopup.selectedTag forKey:@"cameraDeviceNumber"];
    [defaults setObject:calibrationServerDNSNameOrIPAddress.stringValue forKey:@"calibrationServerDNSNameOrIPAddress"];
    [defaults setBool:showPrefsOnStartup.state forKey:@"showPrefsOnStartup"];
    
    [NSApp stopModal];
    [self close];
    
    SDL_Event event;
    SDL_zero(event);
    event.type = gSDLEventPreferencesChanged;
    event.user.code = (Sint32)0;
    event.user.data1 = NULL;
    event.user.data2 = NULL;
    SDL_PushEvent(&event);
}

@end

void *initPreferences(void)
{
    ARLOGi("initPreferences\n");
    
    // Register the preference defaults early.
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithBool:YES], @"showPrefsOnStartup",
                                 nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];

    NSLog(@"showPrefsOnStartup=%s.\n", ([[NSUserDefaults standardUserDefaults] boolForKey:@"showPrefsOnStartup"] ? "true" : "false"));
    
    PrefsWindowController *pwc = [[PrefsWindowController alloc] initWithWindowNibName:@"PrefsWindow"];
    
    // Register the Preferences menu item in the app menu.
    NSMenu *appMenu = [[[NSApp mainMenu] itemAtIndex: 0] submenu];
    for (NSMenuItem *mi in appMenu.itemArray) {
        if ([mi.title isEqualToString:@"Preferences…"]) {
            mi.target = pwc;
            mi.action = @selector(showWindow:);
            mi.enabled = TRUE;
            break;
        }
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"showPrefsOnStartup"]) {
        showPreferences((__bridge void *)pwc);
    }
    return ((void *)CFBridgingRetain(pwc));
}

void showPreferences(void *preferences)
{
    PrefsWindowController *pwc = (__bridge PrefsWindowController *)preferences;
    if (pwc) {
        [pwc showWindow:nil];
        //[NSApp runModalForWindow:pwc.window];
        //NSLog(@"Back from modal\n");
    }
}

int getCameraIndex(void)
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    return ((int)[defaults integerForKey:@"cameraDeviceNumber"]);
}


