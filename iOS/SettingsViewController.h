//
//  SettingsViewController.h
//  ARToolKit Camera Calibrator
//
//  Created by Patrick on 5/10/15.
//  Copyright (c) 2015 DAQRI. All rights reserved.
//

#import <UIKit/UIKit.h>
static NSString* const kSettingForceLandscapeStr = @"SettingForceLandscape";
static NSString* const kSettingCameraResolutionStr = @"SettingCameraResolution";
static NSString* const kSettingCameraSourceStr = @"SettingCameraSource";
static NSString* const kSettingPaperSizeStr = @"SettingPaperSize";

static NSString* const kCameraSourceFront = @"Front";
static NSString* const kCameraSourceRear = @"Rear";

static NSString* const kPaperSizeA4Str = @"A4";
static NSString* const kPaperSizeUSLetterStr = @"US Letter";
@interface SettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@end
