/*
 *  SettingsViewController.h
 *  ARToolKit6
 *
 *  This file is part of ARToolKit.
 *
 *  ARToolKit is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  ARToolKit is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with ARToolKit.  If not, see <http://www.gnu.org/licenses/>.
 *
 *  As a special exception, the copyright holders of this library give you
 *  permission to link this library with independent modules to produce an
 *  executable, regardless of the license terms of these independent modules, and to
 *  copy and distribute the resulting executable under terms of your choice,
 *  provided that you also meet, for each linked independent module, the terms and
 *  conditions of the license of that module. An independent module is a module
 *  which is neither derived from nor based on this library. If you modify this
 *  library, you may extend this exception to your version of the library, but you
 *  are not obligated to do so. If you do not wish to do so, delete this exception
 *  statement from your version.
 *
 *  Copyright 2015-2017 Daqri LLC. All Rights Reserved.
 *
 *  Author(s): Philip Lamb, Patrick Felong.
 *
 */


#import <UIKit/UIKit.h>

static NSString* const kSettingCameraResolutionStr = @"SettingCameraResolution";
static NSString* const kSettingCameraSourceStr = @"SettingCameraSource";
static NSString* const kSettingPaperSizeStr = @"SettingPaperSize";
static NSString *const kSettingCalibrationPatternType = @"calibrationPatternType";
static NSString *const kSettingCalibrationPatternSizeWidth = @"calibrationPatternSizeWidth";
static NSString *const kSettingCalibrationPatternSizeHeight = @"calibrationPatternSizeHeight";
static NSString *const kSettingCalibrationPatternSpacing = @"calibrationPatternSpacing";
static NSString *const kSettingCalibrationSave = @"calibrationSave";
static NSString *const kSettingCalibrationServerUploadCanonical = @"calibrationServerUploadCanonical";
static NSString *const kSettingCalibrationServerUploadUser = @"calibrationServerUploadUser";
static NSString *const kSettingCalibrationServerUploadURL = @"calibrationServerUploadURL";
static NSString *const kSettingCalibrationServerAuthenticationToken = @"calibrationServerAuthenticationToken";

static NSString* const kCameraSourceFront = @"Front";
static NSString* const kCameraSourceRear = @"Rear";

static NSString* const kPaperSizeA4Str = @"A4";
static NSString* const kPaperSizeUSLetterStr = @"US Letter";

static NSString *const kCalibrationPatternTypeChessboardStr = @"Chessboard";
static NSString *const kCalibrationPatternTypeCirclesStr = @"Circles";
static NSString *const kCalibrationPatternTypeAsymmetricCirclesStr = @"Asymmetric circles";

@interface SettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@end
