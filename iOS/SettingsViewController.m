//
//  SettingsViewController.m
//  ARToolKit Camera Calibrator
//
//  Created by Patrick on 5/10/15.
//  Copyright (c) 2015 DAQRI. All rights reserved.
//

#import "ARViewController.h"
#import "../prefs.h"
#import "SettingsViewController.h"

@interface SettingsViewController ()
- (IBAction)goBack:(id)sender;
- (IBAction)csatEdited:(id)sender;
- (IBAction)csuuEdited:(id)sender;
@property (nonatomic, strong) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UITableViewCell *cameraResolutionCell;
@property (nonatomic, strong) IBOutlet UITableViewCell *changeCameraCell;
@property (nonatomic, strong) IBOutlet UITableViewCell *paperSizeCell;
@property (strong, nonatomic) IBOutlet UITableViewCell *csuuCell;
@property (strong, nonatomic) IBOutlet UITextField *calibrationServerUploadURL;
@property (strong, nonatomic) IBOutlet UITableViewCell *csatCell;
@property (strong, nonatomic) IBOutlet UITextField *calibrationServerAuthenticationToken;
@property (nonatomic, strong) IBOutlet UILabel *cameraResolutionSubLabel;
@property (nonatomic, strong) IBOutlet UILabel *cameraSourceSubLabel;
@property (nonatomic, strong) IBOutlet UILabel *paperSizeCellSubLabel;
@property (nonatomic, strong) IBOutlet UISwitch *forceLandscapeSwitch;
@property (nonatomic, strong) NSArray *cameraResPresets;
@end



@implementation SettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.cameraResPresets = [NSArray arrayWithObjects:@"cif", @"480p" /*@"vga"*/, @"720p", @"1080p", @"low", @"medium", @"high", nil];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"calibrationServerUploadURL"] != nil) {
        [self.calibrationServerUploadURL setText:[defaults objectForKey:@"calibrationServerUploadURL"]];
    }
    [self.calibrationServerUploadURL setPlaceholder:@CALIBRATION_SERVER_UPLOAD_URL_DEFAULT];
    
    if ([defaults objectForKey:@"calibrationServerAuthenticationToken"] != nil) {
        [self.calibrationServerAuthenticationToken setText:[defaults objectForKey:@"calibrationServerAuthenticationToken"]];
    }
    [self.calibrationServerAuthenticationToken setPlaceholder:@CALIBRATION_SERVER_AUTHENTICATION_TOKEN_DEFAULT];

    if ([defaults objectForKey:kSettingCameraResolutionStr] != nil) [self.cameraResolutionSubLabel setText:[defaults objectForKey:kSettingCameraResolutionStr]];
    if ([defaults objectForKey:kSettingCameraSourceStr] != nil) [self.cameraSourceSubLabel setText:[defaults objectForKey:kSettingCameraSourceStr]];
    if ([defaults objectForKey:kSettingPaperSizeStr] != nil) [self.paperSizeCellSubLabel setText:[defaults objectForKey:kSettingPaperSizeStr]];
}

- (IBAction)goBack:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:PreferencesChangedNotification object:self];
}

- (IBAction)csatEdited:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:self.calibrationServerAuthenticationToken.text forKey:@"calibrationServerAuthenticationToken"];
}

- (IBAction)csuuEdited:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setObject:self.calibrationServerUploadURL.text forKey:@"calibrationServerUploadURL"];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return @"CAMERA SETTINGS";
    if (section == 1) return @"PRINT SETTINGS";
    if (section == 2) return @"CALIBRATION SERVER SETTINGS";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 2;
    if (section == 1) return 1;
    if (section == 2) return 2;
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
    if (cameraSource) {
        if      ([cameraSource isEqualToString:kCameraSourceFront]) return strdup("-position=front");
        else if ([cameraSource isEqualToString:kCameraSourceRear]) return strdup("-position=rear");
    }
    return NULL;
}

char *getPreferenceCameraResolutionToken(void *preferences)
{
    NSString *cameraResolution = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingCameraResolutionStr];
    if (cameraResolution) {
        return (strdup([NSString stringWithFormat:@"-preset=%@", cameraResolution].UTF8String));
    }
    return NULL;
}

char *getPreferenceCalibrationServerUploadURL(void *preferences)
{
    NSString *csuu = [[NSUserDefaults standardUserDefaults] stringForKey:@"calibrationServerUploadURL"];
    if (csuu) return (strdup(csuu.UTF8String));
    return NULL;
}

char *getPreferenceCalibrationServerAuthenticationToken(void *preferences)
{
    NSString *csat = [[NSUserDefaults standardUserDefaults] stringForKey:@"calibrationServerAuthenticationToken"];
    if (csat) return (strdup(csat.UTF8String));
    return NULL;
}

void preferencesFinal(void **preferences_p)
{
}

