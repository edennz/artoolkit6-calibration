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
    IBOutlet NSTextField *calibrationServerUploadURL;
    IBOutlet NSTextField *calibrationServerAuthenticationToken;
    IBOutlet NSPopUpButton *cameraInputPopup;
}
- (IBAction)okSelected:(NSButton *)sender;
@end

#endif // __OBJC__
#endif // !__PrefsWindowController_h__
