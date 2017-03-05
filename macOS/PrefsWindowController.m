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
#import "../prefs.h"

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
    } else if (sil->count == 0) {
        ARLOGe("No video sources connected.\n");
        cameraInputPopup.enabled = FALSE;
    } else {
        NSString *cot = [defaults stringForKey:@"cameraOpenToken"];
        int selectedItemIndex = 0;
        for (int i = 0; i < sil->count; i++) {
            [cameraInputPopup addItemWithTitle:[NSString stringWithUTF8String:sil->info[i].name]];
            [[cameraInputPopup itemAtIndex:i] setRepresentedObject:[NSString stringWithUTF8String:sil->info[i].open_token]];
            if (cot && sil->info[i].open_token && strcmp(cot.UTF8String, sil->info[i].open_token) == 0) {
                selectedItemIndex = i;
            }
        }
        [cameraInputPopup selectItemAtIndex:selectedItemIndex];
        cameraInputPopup.enabled = TRUE;
    }
    
    NSString *cp = [defaults stringForKey:@"cameraPreset"];
    if (cp) [cameraPresetPopup selectItemWithTitle:cp];
    
    NSString *csuu = [defaults stringForKey:@"calibrationServerUploadURL"];
    calibrationServerUploadURL.stringValue = (csuu ? csuu : @"");
    NSString *csat = [defaults stringForKey:@"calibrationServerAuthenticationToken"];
    calibrationServerAuthenticationToken.stringValue = (csat ? csat : @"");
    
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
    NSString *cot = cameraInputPopup.selectedItem.representedObject;
    [defaults setObject:cameraPresetPopup.selectedItem.title forKey:@"cameraPreset"];
    [defaults setObject:cot forKey:@"cameraOpenToken"];
    [defaults setObject:calibrationServerUploadURL.stringValue forKey:@"calibrationServerUploadURL"];
    [defaults setObject:calibrationServerAuthenticationToken.stringValue forKey:@"calibrationServerAuthenticationToken"];
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

//
// C interface to our ObjC preferences class.
//

void *initPreferences(void)
{
    // Register the preference defaults early.
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithBool:YES], @"showPrefsOnStartup",
                                 nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];

    //NSLog(@"showPrefsOnStartup=%s.\n", ([[NSUserDefaults standardUserDefaults] boolForKey:@"showPrefsOnStartup"] ? "true" : "false"));
    
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
        [pwc showWindow:pwc];
        [pwc.window makeKeyAndOrderFront:pwc];
        //[NSApp runModalForWindow:pwc.window];
        //NSLog(@"Back from modal\n");
    }
}

char *getPreferenceCameraOpenToken(void)
{
    NSString *cot = [[NSUserDefaults standardUserDefaults] stringForKey:@"cameraOpenToken"];
    if (cot) return (strdup(cot.UTF8String));
    return NULL;
}

char *getPreferenceCameraResolutionToken(void)
{
    NSString *cp = [[NSUserDefaults standardUserDefaults] stringForKey:@"cameraPreset"];
    if (cp) {
        char *ret;
        if (asprintf(&ret, "-preset=%s", cp.UTF8String) < 0) {
            ARLOGperror(NULL);
            return NULL;
        }
        return ret;
    }
    return NULL;
}

char *getPreferenceCalibrationServerUploadURL(void)
{
    NSString *csuu = [[NSUserDefaults standardUserDefaults] stringForKey:@"calibrationServerUploadURL"];
    if (csuu) return (strdup(csuu.UTF8String));
    return NULL;
}

char *getPreferenceCalibrationServerAuthenticationToken(void)
{
    NSString *csat = [[NSUserDefaults standardUserDefaults] stringForKey:@"calibrationServerAuthenticationToken"];
    if (csat) return (strdup(csat.UTF8String));
    return NULL;
}

void preferencesFinal(void **preferences_p)
{
    if (preferences_p) {
        CFRelease(*preferences_p);
        *preferences_p = NULL;
    }
}

