/*
 *  SettingsViewController.mm
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


#import "ARViewController.h"
#import "../prefs.hpp"
#import "SettingsViewController.h"

@interface SettingsViewController ()
- (IBAction)goBack:(id)sender;
- (IBAction)csatEdited:(id)sender;
- (IBAction)csuuEdited:(id)sender;
@property (nonatomic, strong) IBOutlet UITableView *tableView;

@property (nonatomic, strong) IBOutlet UITableViewCell *cameraResolutionCell;
@property (nonatomic, strong) IBOutlet UILabel *cameraResolutionSubLabel;
@property (nonatomic, strong) NSArray *cameraResPresets;

@property (nonatomic, strong) IBOutlet UITableViewCell *changeCameraCell;
@property (nonatomic, strong) IBOutlet UILabel *cameraSourceSubLabel;

@property (nonatomic, strong) IBOutlet UITableViewCell *paperSizeCell;
@property (nonatomic, strong) IBOutlet UILabel *paperSizeCellSubLabel;

@property (strong, nonatomic) IBOutlet UITableViewCell *csuuCell;
@property (weak, nonatomic) IBOutlet UITextField *calibrationServerUploadURL;

@property (strong, nonatomic) IBOutlet UITableViewCell *csatCell;
@property (weak, nonatomic) IBOutlet UITextField *calibrationServerAuthenticationToken;

@property (strong, nonatomic) IBOutlet UITableViewCell *calibrationPatternCell;
@property (weak, nonatomic) IBOutlet UISegmentedControl *calibrationPatternTypeControl;
- (IBAction)calibrationPatternTypeChanged:(UISegmentedControl *)sender;
@property (weak, nonatomic) IBOutlet UIStepper *calibrationPatternSizeWidthStepper;
@property (weak, nonatomic) IBOutlet UIStepper *calibrationPatternSizeHeightStepper;
- (IBAction)calibrationPatternSizeWidthChanged:(id)sender;
- (IBAction)calibrationPatternSizeHeightChanged:(id)sender;
@property (weak, nonatomic) IBOutlet UILabel *calibrationPatternSizeWidthLabel;
@property (weak, nonatomic) IBOutlet UILabel *calibrationPatternSizeHeightLabel;
@property (weak, nonatomic) IBOutlet UITextField *calibrationPatternSpacing;
- (IBAction)calibrationPatternSpacingChanged:(UITextField *)sender;

@end



@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.cameraResPresets = [NSArray arrayWithObjects:@"cif", @"480p" /*@"vga"*/, @"720p", @"1080p", @"low", @"medium", @"high", nil];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kSettingCalibrationServerUploadURL] != nil) {
        [self.calibrationServerUploadURL setText:[defaults objectForKey:kSettingCalibrationServerUploadURL]];
    }
    [self.calibrationServerUploadURL setPlaceholder:@CALIBRATION_SERVER_UPLOAD_URL_DEFAULT];
    
    if ([defaults objectForKey:kSettingCalibrationServerAuthenticationToken] != nil) {
        [self.calibrationServerAuthenticationToken setText:[defaults objectForKey:kSettingCalibrationServerAuthenticationToken]];
    }
    [self.calibrationServerAuthenticationToken setPlaceholder:@CALIBRATION_SERVER_AUTHENTICATION_TOKEN_DEFAULT];

    if ([defaults objectForKey:kSettingCameraResolutionStr] != nil) [self.cameraResolutionSubLabel setText:[defaults objectForKey:kSettingCameraResolutionStr]];
    if ([defaults objectForKey:kSettingCameraSourceStr] != nil) [self.cameraSourceSubLabel setText:[defaults objectForKey:kSettingCameraSourceStr]];
    if ([defaults objectForKey:kSettingPaperSizeStr] != nil) [self.paperSizeCellSubLabel setText:[defaults objectForKey:kSettingPaperSizeStr]];
    
    Calibration::CalibrationPatternType patternType = CALIBRATION_PATTERN_TYPE_DEFAULT;
    NSString *patternTypeStr = [defaults objectForKey:kSettingCalibrationPatternType];
    if (patternTypeStr.length != 0) {
        if ([patternTypeStr isEqualToString:kCalibrationPatternTypeChessboardStr]) patternType = Calibration::CalibrationPatternType::CHESSBOARD;
        else if ([patternTypeStr isEqualToString:kCalibrationPatternTypeCirclesStr]) patternType = Calibration::CalibrationPatternType::CIRCLES_GRID;
        else if ([patternTypeStr isEqualToString:kCalibrationPatternTypeAsymmetricCirclesStr]) patternType = Calibration::CalibrationPatternType::ASYMMETRIC_CIRCLES_GRID;
    }
    switch (patternType) {
        case Calibration::CalibrationPatternType::CHESSBOARD: self.calibrationPatternTypeControl.selectedSegmentIndex = 0; break;
        case Calibration::CalibrationPatternType::CIRCLES_GRID: self.calibrationPatternTypeControl.selectedSegmentIndex = 1; break;
        case Calibration::CalibrationPatternType::ASYMMETRIC_CIRCLES_GRID: self.calibrationPatternTypeControl.selectedSegmentIndex = 2; break;
    }
    
    int w = (int)[defaults integerForKey:kSettingCalibrationPatternSizeWidth];
    int h = (int)[defaults integerForKey:kSettingCalibrationPatternSizeHeight];
    if (w < 1 || h < 1) {
        w = Calibration::CalibrationPatternSizes[patternType].width;
        h = Calibration::CalibrationPatternSizes[patternType].height;
    }
    self.calibrationPatternSizeWidthStepper.value = w;
    self.calibrationPatternSizeHeightStepper.value = h;
    [self calibrationPatternSizeWidthChanged:self.calibrationPatternSizeWidthStepper];
    [self calibrationPatternSizeHeightChanged:self.calibrationPatternSizeHeightStepper];
    
    float f = [defaults floatForKey:kSettingCalibrationPatternSpacing];
    if (f <= 0.0f) f = Calibration::CalibrationPatternSpacings[patternType];
    self.calibrationPatternSpacing.text = [NSString stringWithFormat:@"%.2f", f];
}

- (IBAction)goBack:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:PreferencesChangedNotification object:self];
}

- (IBAction)csatEdited:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:self.calibrationServerAuthenticationToken.text forKey:kSettingCalibrationServerAuthenticationToken];
}

- (IBAction)csuuEdited:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:self.calibrationServerUploadURL.text forKey:kSettingCalibrationServerUploadURL];
}

- (void)selectCameraResolution
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Select Camera Resolution" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    for (NSString *preset in self.cameraResPresets) {
        [alertController addAction:[UIAlertAction actionWithTitle:preset style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [defaults setObject:preset forKey:kSettingCameraResolutionStr];
            [self.cameraResolutionSubLabel setText:preset]; }]];
    }
    [alertController.popoverPresentationController setSourceView:self.cameraResolutionCell];
    [self presentViewController:alertController animated:YES completion:^(void) {
        [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1] animated:YES];
        [defaults synchronize];
    }];
}

- (void)selectCameraSource
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Select Camera" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alertController addAction:[UIAlertAction actionWithTitle:kCameraSourceFront style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [defaults setObject:kCameraSourceFront forKey:kSettingCameraSourceStr];
        [self.cameraSourceSubLabel setText:kCameraSourceFront];
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:kCameraSourceRear style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [defaults setObject:kCameraSourceRear forKey:kSettingCameraSourceStr];
        [self.cameraSourceSubLabel setText:kCameraSourceRear];
    }]];
    [alertController.popoverPresentationController setSourceView:self.changeCameraCell];
    [self presentViewController:alertController animated:YES completion:^(void) {
        [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1] animated:YES];
        [defaults synchronize];
    }];
}

- (void)selectPaperSize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Paper Size" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alertController addAction:[UIAlertAction actionWithTitle:kPaperSizeA4Str style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [defaults setObject:kPaperSizeA4Str forKey:kSettingPaperSizeStr];
        [self.paperSizeCellSubLabel setText:kPaperSizeA4Str]; }]];
    [alertController addAction:[UIAlertAction actionWithTitle:kPaperSizeUSLetterStr style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [defaults setObject:kPaperSizeUSLetterStr forKey:kSettingPaperSizeStr];
        [self.paperSizeCellSubLabel setText:kPaperSizeUSLetterStr]; }]];
    [alertController.popoverPresentationController setSourceView:self.paperSizeCell];
    [self presentViewController:alertController animated:YES completion:^(void) {
        [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2] animated:YES];
        [defaults synchronize];
    }];
}

- (IBAction)calibrationPatternTypeChanged:(UISegmentedControl *)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    Calibration::CalibrationPatternType patternType;
    switch (sender.selectedSegmentIndex) {
        case 0:
            [defaults setObject:kCalibrationPatternTypeChessboardStr forKey:kSettingCalibrationPatternType];
            patternType = Calibration::CalibrationPatternType::CHESSBOARD;
            break;
        case 1:
            [defaults setObject:kCalibrationPatternTypeCirclesStr forKey:kSettingCalibrationPatternType];
            patternType = Calibration::CalibrationPatternType::CIRCLES_GRID;
            break;
        case 2:
            [defaults setObject:kCalibrationPatternTypeAsymmetricCirclesStr forKey:kSettingCalibrationPatternType];
            patternType = Calibration::CalibrationPatternType::ASYMMETRIC_CIRCLES_GRID;
            break;
        default:
            [defaults setObject:nil forKey:kSettingCalibrationPatternType];
            patternType = CALIBRATION_PATTERN_TYPE_DEFAULT;
            break;
    }
    self.calibrationPatternSizeWidthStepper.value = Calibration::CalibrationPatternSizes[patternType].width;
    self.calibrationPatternSizeHeightStepper.value = Calibration::CalibrationPatternSizes[patternType].height;
    self.calibrationPatternSpacing.text = [NSString stringWithFormat:@"%.2f", Calibration::CalibrationPatternSpacings[patternType]];
    [self calibrationPatternSizeWidthChanged:self.calibrationPatternSizeWidthStepper];
    [self calibrationPatternSizeHeightChanged:self.calibrationPatternSizeHeightStepper];
    [self calibrationPatternSpacingChanged:self.calibrationPatternSpacing];
}

- (IBAction)calibrationPatternSizeWidthChanged:(UIStepper *)sender
{
    self.calibrationPatternSizeWidthLabel.text = [NSString stringWithFormat:@"%d", (int)sender.value];
    [[NSUserDefaults standardUserDefaults] setInteger:(int)sender.value forKey:kSettingCalibrationPatternSizeWidth];
}

- (IBAction)calibrationPatternSizeHeightChanged:(UIStepper *)sender
{
    self.calibrationPatternSizeHeightLabel.text = [NSString stringWithFormat:@"%d", (int)sender.value];
    [[NSUserDefaults standardUserDefaults] setInteger:(int)sender.value forKey:kSettingCalibrationPatternSizeHeight];
}

- (IBAction)calibrationPatternSpacingChanged:(UITextField *)sender
{
    [[NSUserDefaults standardUserDefaults] setFloat:[sender.text floatValue] forKey:kSettingCalibrationPatternSpacing];
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return @"CAMERA SETTINGS";
    if (section == 1) return @"PRINT SETTINGS";
    if (section == 2) return @"CALIBRATION SERVER SETTINGS";
    if (section == 3) return @"CALIBRATION PATTERN SETTINGS";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 2;
    if (section == 1) return 1;
    if (section == 2) return 2;
    if (section == 3) return 1;
   return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return self.cameraResolutionCell;
        if (indexPath.row == 1) return self.changeCameraCell;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) return self.paperSizeCell;
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) return self.csuuCell;
        if (indexPath.row == 1) return self.csatCell;
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) return self.calibrationPatternCell;
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self selectCameraResolution];
        if (indexPath.row == 1) [self selectCameraSource];
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) [self selectPaperSize];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return 62.0f;
        if (indexPath.row == 1) return 62.0f;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) return 62.0f;
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) return 76.0f;
        if (indexPath.row == 1) return 76.0f;
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) return 186.0f;
   }
    return 0;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

void *initPreferences(void)
{
    return (NULL);
}

void showPreferences(void *preferences)
{
}

char *getPreferenceCameraOpenToken(void *preferences)
{
    NSString *cameraSource = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingCameraSourceStr];
    if (cameraSource.length != 0) {
        if      ([cameraSource isEqualToString:kCameraSourceFront]) return strdup("-position=front");
        else if ([cameraSource isEqualToString:kCameraSourceRear]) return strdup("-position=rear");
    }
    return NULL;
}

char *getPreferenceCameraResolutionToken(void *preferences)
{
    NSString *cameraResolution = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingCameraResolutionStr];
    if (cameraResolution.length != 0) {
        return (strdup([NSString stringWithFormat:@"-preset=%@", cameraResolution].UTF8String));
    }
    return NULL;
}

char *getPreferenceCalibrationServerUploadURL(void *preferences)
{
    NSString *csuu = [[NSUserDefaults standardUserDefaults] stringForKey:kSettingCalibrationServerUploadURL];
    if (csuu.length != 0) return (strdup(csuu.UTF8String));
    return NULL;
}

char *getPreferenceCalibrationServerAuthenticationToken(void *preferences)
{
    NSString *csat = [[NSUserDefaults standardUserDefaults] stringForKey:kSettingCalibrationServerAuthenticationToken];
    if (csat.length != 0) return (strdup(csat.UTF8String));
    return NULL;
}

Calibration::CalibrationPatternType getPreferencesCalibrationPatternType(void *preferences)
{
    Calibration::CalibrationPatternType patternType = CALIBRATION_PATTERN_TYPE_DEFAULT;
    NSString *patternTypeStr = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingCalibrationPatternType];
    if (patternTypeStr.length != 0) {
        if ([patternTypeStr isEqualToString:kCalibrationPatternTypeChessboardStr]) patternType = Calibration::CalibrationPatternType::CHESSBOARD;
        else if ([patternTypeStr isEqualToString:kCalibrationPatternTypeCirclesStr]) patternType = Calibration::CalibrationPatternType::CIRCLES_GRID;
        else if ([patternTypeStr isEqualToString:kCalibrationPatternTypeAsymmetricCirclesStr]) patternType = Calibration::CalibrationPatternType::ASYMMETRIC_CIRCLES_GRID;
    }
    return patternType;
}

cv::Size getPreferencesCalibrationPatternSize(void *preferences)
{
    int w = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kSettingCalibrationPatternSizeWidth];
    int h = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kSettingCalibrationPatternSizeHeight];
    if (w > 0 && h > 0) return cv::Size(w, h);
    
    return Calibration::CalibrationPatternSizes[getPreferencesCalibrationPatternType(preferences)];
}

float getPreferencesCalibrationPatternSpacing(void *preferences)
{
    float f = [[NSUserDefaults standardUserDefaults] floatForKey:kSettingCalibrationPatternSpacing];
    if (f > 0.0f) return f;
    
    return Calibration::CalibrationPatternSpacings[getPreferencesCalibrationPatternType(preferences)];
}

void preferencesFinal(void **preferences_p)
{
}

