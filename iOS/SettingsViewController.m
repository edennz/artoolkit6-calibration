//
//  SettingsViewController.m
//  ARToolKit Camera Calibrator
//
//  Created by Patrick on 5/10/15.
//  Copyright (c) 2015 DAQRI. All rights reserved.
//

#import "SettingsViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface SettingsViewController ()
-(IBAction)goBack:(id)sender;
@property (nonatomic, strong) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UITableViewCell *forceLandscapeCell;
@property (nonatomic, strong) IBOutlet UITableViewCell *cameraResolutionCell;
@property (nonatomic, strong) IBOutlet UITableViewCell *changeCameraCell;
@property (nonatomic, strong) IBOutlet UITableViewCell *paperSizeCell;
@property (nonatomic, strong) IBOutlet UILabel *forceLandscapeSubLabel;
@property (nonatomic, strong) IBOutlet UILabel *cameraResolutionSubLabel;
@property (nonatomic, strong) IBOutlet UILabel *cameraSourceSubLabel;
@property (nonatomic, strong) IBOutlet UILabel *paperSizeCellSubLabel;
@property (nonatomic, strong) IBOutlet UISwitch *forceLandscapeSwitch;
@property (nonatomic, strong) NSArray *cameraResPresets;
@end



@implementation SettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.cameraResPresets = [NSArray arrayWithObjects:@"cif", @"480p", @"vga", @"720p", @"1080p", @"low", @"medium", @"high", nil];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [self.forceLandscapeSwitch setOn:[defaults boolForKey:kSettingForceLandscapeStr]];
    if ([defaults objectForKey:kSettingCameraResolutionStr] != nil) [self.cameraResolutionSubLabel setText:[defaults objectForKey:kSettingCameraResolutionStr]];
    if ([defaults objectForKey:kSettingCameraSourceStr] != nil) [self.cameraSourceSubLabel setText:[defaults objectForKey:kSettingCameraSourceStr]];
    if ([defaults objectForKey:kSettingPaperSizeStr] != nil) [self.paperSizeCellSubLabel setText:[defaults objectForKey:kSettingPaperSizeStr]];
}

- (IBAction)goBack:(id)sender {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleForceLandscape {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL forceLandscape = ![defaults boolForKey:kSettingForceLandscapeStr];
    [self.forceLandscapeSwitch setOn:forceLandscape animated:YES];
    [defaults setBool:forceLandscape forKey:kSettingForceLandscapeStr];
    [defaults synchronize];
}

- (void)selectCameraResolution {
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

- (void)selectCameraSource {
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

- (void)selectPaperSize {
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"DISPLAY SETTINGS";
    if (section == 1) return @"CAMERA SETTINGS";
    if (section == 2) return @"PRINT SETTINGS";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return self.forceLandscapeCell;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return self.cameraResolutionCell;
        if (indexPath.row == 1) return self.changeCameraCell;
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) return self.paperSizeCell;
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self toggleForceLandscape];
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) [self selectCameraResolution];
        if (indexPath.row == 1) [self selectCameraSource];
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) [self selectPaperSize];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 2;
    if (section == 2) return 1;
    return 0;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (indexPath.row == 0) return 70.0;
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) return 62.0;
        if (indexPath.row == 1) return 62.0;
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) return 62.0;
    }
    return 0;
}

// On iOS 6.0 and later, we must explicitly report which orientations this view controller supports.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSettingForceLandscapeStr])
        return UIInterfaceOrientationMaskLandscapeLeft;
    else return UIInterfaceOrientationMaskAll;
}
@end
