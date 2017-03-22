//
//  ARViewController.h
//  ARToolKit Camera Calibrator
//
//  Created by Patrick on 5/10/15.
//  Copyright (c) 2015 DAQRI. All rights reserved.
//

#include "fileUploader.h"

#ifdef __OBJC__
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AR6/AR/ar.h>
#import <AR6/ARVideo/video.h>
#import <AR6/ARG/arg.h>
#import "ARView.h"

#import <opencv2/core/fast_math.hpp>
#import <opencv2/core/types_c.h>

#define FONT_SIZE 6.8f

@class ARView; @class CalibCameraWrapper;
@interface ARViewController : UIViewController <CameraVideoTookPictureDelegate, ARViewTouchDelegate, EAGLViewTookSnapshotDelegate, UIDocumentInteractionControllerDelegate>
{
     
}

- (IBAction)start;
- (IBAction)stop;
- (void) processFrame:(AR2VideoBufferT *)buffer;
- (void)takeSnapshot;

@property (readonly) ARView *glView;
@property (readonly) int gDisplayOrientation;
@property (readonly) ARGL_CONTEXT_SETTINGS_REF gArglSettings;
@property (readonly) ARGL_CONTEXT_SETTINGS_REF gArglSettingsCornerFinderImage;

@property (readonly, nonatomic, getter=isRunning) BOOL running;
@property (nonatomic, getter=isPaused) BOOL paused;

// Frame interval defines how many display frames must pass between each time the
// display link fires. The display link will only fire 30 times a second when the
// frame internal is two on a display that refreshes 60 times a second. The default
// frame interval setting of one will fire 60 times a second when the display refreshes
// at 60 times a second. A frame interval setting of less than one results in undefined
// behavior.
@property (nonatomic) NSInteger runLoopInterval;


- (BOOL)cornerFinderResultsLockAndFetchCornerFlag:(int *)cornerFlag cornerCount:(int *)cornerCount corners:(CvPoint2D32f **)corners;
- (BOOL)cornerFinderResultsUnlock;

@property (nonatomic, retain) IBOutlet UIView *overlays;
- (IBAction)handleBackButton:(id)sender;
@property (retain, nonatomic) IBOutlet UIBarButtonItem *menuButtonItem;
- (IBAction)showMenu:(id)sender;

@end

#endif // __OBJC__

extern FILE_UPLOAD_HANDLE_t *fileUploadHandle;
extern bool capture(const int capturedImageNum);
extern void calib(ARParam *param_out, ARdouble *err_min_out, ARdouble *err_avg_out, ARdouble *err_max_out);
extern void saveParam(const ARParam *param, ARdouble err_min, ARdouble err_avg, ARdouble err_max);

