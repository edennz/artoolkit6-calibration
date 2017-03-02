//
//  PrefsWindowController.h
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 1/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#ifndef __PrefsWindowController_h__
#define __PrefsWindowController_h__

#if __OBJC__

#import <Cocoa/Cocoa.h>

@interface PrefsWindowController : NSWindowController
{
    IBOutlet NSButton *showPrefsOnStartup;
    IBOutlet NSTextField *calibrationServerDNSNameOrIPAddress;
    IBOutlet NSPopUpButton *cameraInputPopup;
}
- (IBAction)okSelected:(NSButton *)sender;
@end

#endif

#ifdef __cplusplus
extern "C" {
#endif

void *initPreferences(void);
void showPreferences(void *preferences);

int getCameraIndex(void);


#ifdef __cplusplus
}
#endif
#endif // !__PrefsWindowController_h__
