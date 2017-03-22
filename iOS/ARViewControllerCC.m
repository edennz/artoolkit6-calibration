//
//  ARViewController.m
//  ARToolKit Camera Calibrator
//
//
//  Disclaimer: IMPORTANT:  This Daqri software is supplied to you by Daqri
//  LLC ("Daqri") in consideration of your agreement to the following
//  terms, and your use, installation, modification or redistribution of
//  this Daqri software constitutes acceptance of these terms.  If you do
//  not agree with these terms, please do not use, install, modify or
//  redistribute this Daqri software.
//
//  In consideration of your agreement to abide by the following terms, and
//  subject to these terms, Daqri grants you a personal, non-exclusive
//  license, under Daqri's copyrights in this original Daqri software (the
//  "Daqri Software"), to use, reproduce, modify and redistribute the Daqri
//  Software, with or without modifications, in source and/or binary forms;
//  provided that if you redistribute the Daqri Software in its entirety and
//  without modifications, you must retain this notice and the following
//  text and disclaimers in all such redistributions of the Daqri Software.
//  Neither the name, trademarks, service marks or logos of Daqri LLC may
//  be used to endorse or promote products derived from the Daqri Software
//  without specific prior written permission from Daqri.  Except as
//  expressly stated in this notice, no other rights or licenses, express or
//  implied, are granted by Daqri herein, including but not limited to any
//  patent rights that may be infringed by your derivative works or by other
//  works in which the Daqri Software may be incorporated.
//
//  The Daqri Software is provided by Daqri on an "AS IS" basis.  DAQRI
//  MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
//  THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
//  FOR A PARTICULAR PURPOSE, REGARDING THE DAQRI SOFTWARE OR ITS USE AND
//  OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
//
//  IN NO EVENT SHALL DAQRI BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
//  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
//  MODIFICATION AND/OR DISTRIBUTION OF THE DAQRI SOFTWARE, HOWEVER CAUSED
//  AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
//  STRICT LIABILITY OR OTHERWISE, EVEN IF DAQRI HAS BEEN ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  Copyright 2015 Daqri LLC. All Rights Reserved.
//  Copyright 2010-2015 ARToolworks, Inc. All rights reserved.
//
//  Author(s): Philip Lamb, Patrick Felong
//


/*
 * Design notes:
 *
 * New frames arrive on the main thread via processFrame, and a copy of
 * both planes is made.
 *
 * If processing of frames (looking for the chessboard) is not needed, then a marker is
 * set that a new frame has arrived. Upload of this frame will be done on the OpenGL thread.
 * If processing of frames is active, then on the first frame, the cornerFinder thread
 * will be waiting, and the luma channel of the frame will be copied into the thread's data
 * and the thread started. On subsequent incoming frames, a check will be done for any
 * previous results from the cornerFinderThread first. If new results are available, the
 * luma for the processed frame will be copied again and a flag set that it should be
 * displayed, and the corner locations will be copied out.
 *
 * On the OpenGL thread, background frame upload is done,
 * then (if processing active) the drawing of the luma of the most recent frame processed,
 * and corners found.
 *
 * User interaction with this process comes via touches on the surface (delivered via
 * the ARView). Touches are processed on the main thread. If a touch
 * has been found, the most recent results are copied, and if 10 results have been copied,
 * then calibration proceeds, followed by saving of the calibration parameters. Finally,
 * an index file is written for processing by the upload thread.
 *
 * The upload thread pushes form data and the calibration file to the server.
 *
 */

#import "ARViewController.h"
#import "SettingsViewController.h"
#import "ARView.h"
#import "CameraFocusView.h"

#include "flow.h"
#include "calc.h"

#include "thread_sub.h"
#include <opencv2/core/core_c.h>
#include <opencv2/calib3d/calib3d_c.h>
#include <opencv2/imgproc/imgproc_c.h>
#include <pthread.h>

#import <Eden/EdenMessage.h>


// ============================================================================
//	Types
// ============================================================================

typedef struct {
    ARUint8*             videoFrame;
    IplImage            *calibImage;
    int                  chessboardCornerNumX;
    int                  chessboardCornerNumY;
    int                  cornerFlag ;
    int                  cornerCount;
    CvPoint2D32f        *corners;
} CORNER_FINDER_DATA_T;

// ============================================================================
//	Constants
// ============================================================================

#define      CHESSBOARD_CORNER_NUM_X        7
#define      CHESSBOARD_CORNER_NUM_Y        5
#define      CHESSBOARD_PATTERN_WIDTH      30.0
#define      CALIB_IMAGE_NUM               10
#define      SAVE_FILENAME                 "camera_para.dat"

// Data upload.
#define QUEUE_DIR "queue"
#define QUEUE_INDEX_FILE_EXTENSION "upload"
#define UPLOAD_POST_URL "https://omega.artoolworks.com/app/calib_camera/upload.php"
#define UPLOAD_STATUS_HIDE_AFTER_SECONDS 9.0f


//#include <openssl/md5.h>
// Rather than including full OpenSSL header tree, just provide prototype for MD5().
// Usage is here: http://www.openssl.org/docs/crypto/md5.html.
#define MD5_DIGEST_LENGTH 16
#ifdef __cplusplus
extern "C" {
#endif
unsigned char *MD5(const unsigned char *d, size_t n, unsigned char *md);
#ifdef __cplusplus
}
#endif

// Until we implement nonce-based hashing, use of the plain md5 of the shared secret is vulnerable to replay attack.
// The shared secret itself needs to be hidden in the binary.
//#define SHARED_SECRET "com.artoolworks.utils.calib_camera.116D5A95-E17B-266E-39E4-E5DED6C07C53"
#define SHARED_SECRET_MD5 {0x32, 0x57, 0x5a, 0x6f, 0x69, 0xa4, 0x11, 0x5a, 0x25, 0x49, 0xae, 0x55, 0x6b, 0xd2, 0x2a, 0xda} // Keeping the MD5 in hex provides a degree of obfuscation.

#define DEBUG_NO_INTERFACE_AUTOROTATION 1

// ============================================================================
//	Global variables.
// ============================================================================

//
// Calibration.
//

// Prefs.
static int                  gChessboardCornerNumX = 0;
static int                  gChessboardCornerNumY = 0;
static int                  gCalibImageNum = 0;
static float                gChessboardSquareWidth = 0.0f;

static int                  gCameraIndex = 0;
static bool                 gCameraIsFrontFacing = false;

static THREAD_HANDLE_T     *cornerFinderThread = NULL;

// Calibration inputs.
static CvPoint2D32f        *gCornerSet = NULL;
static int                  gVideoWidth = 0;
static int                  gVideoHeight = 0;


//
// Data upload.
//

FILE_UPLOAD_HANDLE_t *fileUploadHandle = NULL;
const char * docsPath = NULL;
const char * queuePath = NULL;

// ============================================================================
//	Function prototypes
// ============================================================================

static void *cornerFinder(THREAD_HANDLE_T *threadHandle);


// ============================================================================
//	Class implementations and functions
// ============================================================================

@interface ARViewController () {
}
- (IBAction)showMenu:(id)sender;
//@property (nonatomic) IBOutlet UIView *glViewPlaceHolder;
@end

@implementation ARViewController {
    
    BOOL            running;
    NSInteger       runLoopInterval;
    NSTimeInterval  runLoopTimePrevious;
    BOOL            videoPaused;
    
    // Video acquisition
    AR2VideoParamT *gVid;
    
    // Marker detection.
    long            gCallCountMarkerDetect;
    
    // Drawing.
    ARView         *glView;
    ARGL_CONTEXT_SETTINGS_REF gArglSettings;
    CameraFocusView *focusView;
    int gDisplayOrientation;

    // Main state.
    struct timeval gStartTime;
    
    //
    // Calibration.
    //
    
    // Corner finder results copy, for display to user.
    ARGL_CONTEXT_SETTINGS_REF gArglSettingsCornerFinderImage;
    ARUint8*             gCornerFinderImage; // The image to which gCorners apply.
    pthread_mutex_t      gCornerFinderResultLock;
    int                  gCornerFlag;
    int                  gCornerCount;
    CvPoint2D32f        *gCorners;
    
    
}

@synthesize glView = glView;
@synthesize gArglSettings = gArglSettings, gArglSettingsCornerFinderImage = gArglSettingsCornerFinderImage, gDisplayOrientation = gDisplayOrientation;
@synthesize running, runLoopInterval;
@synthesize overlays;

#pragma mark Lifecycle
/*
 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        // Custom initialization
    }
    return self;
}
*/

- (void)loadView
{
    self.wantsFullScreenLayout = YES;
    
    // This will be overlaid with the actual AR view.
    NSString *irisImage = nil;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        irisImage = @"Iris-iPad.png";
    }  else { // UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone
        CGSize result = [[UIScreen mainScreen] bounds].size;
        if (result.height == 568 || result.height == 667 || result.height == 736) {
            irisImage = @"Iris-568h.png"; // iPhone 5, iPod touch 5th Gen, etc.
        } else { // result.height == 480
            irisImage = @"Iris.png";
        }
    }
    UIView *irisView = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:irisImage]] autorelease];
    irisView.contentMode = UIViewContentModeScaleToFill;
    irisView.frame = [[UIScreen mainScreen] bounds];
    irisView.userInteractionEnabled = YES;
    self.view = irisView;
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];

    [[NSBundle mainBundle] loadNibNamed:([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"ARViewOverlays-iPad": @"ARViewOverlays") owner:self options:nil]; // Contains connection to the strong property "overlays".
    self.overlays.frame = self.view.frame;
    //if (!focusView) focusView = [[CameraFocusView alloc] initWithFrame:self.view.frame]; // FIXME.
   
    // Init instance variables.
    glView                  = nil;
    gVid                    = NULL;
    gArglSettings           = NULL;
    gArglSettingsCornerFinderImage  = NULL;
    gCornerFinderImage      = NULL;
    gCornerFlag             = 0;
    gCornerCount            = 0;
    gCorners                = NULL;
    gDisplayOrientation     = 0; // range [0-3]. 1=landscape.
    gCallCountMarkerDetect  = 0;
    running                 = FALSE;
    videoPaused             = FALSE;
    runLoopTimePrevious     = CFAbsoluteTimeGetCurrent();
    
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    docsPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] cStringUsingEncoding:NSASCIIStringEncoding];
    NSLog(@"bundle path:%@", bundlePath);
    NSLog(@"docs path:%s", docsPath);
    queuePath = [[NSString stringWithFormat:@"%s/%s", docsPath, QUEUE_DIR] UTF8String];
    
    fileUploadHandle = fileUploaderInit(queuePath, QUEUE_INDEX_FILE_EXTENSION, UPLOAD_POST_URL, UPLOAD_STATUS_HIDE_AFTER_SECONDS);
    if (!fileUploadHandle) {
    	ARLOGe("Error: Could not initialise fileUploadHandle.\n");
    }
    fileUploaderTickle(fileUploadHandle);
    
    // Calibration prefs.
    if( gChessboardCornerNumX == 0 ) gChessboardCornerNumX = CHESSBOARD_CORNER_NUM_X;
    if( gChessboardCornerNumY == 0 ) gChessboardCornerNumY = CHESSBOARD_CORNER_NUM_Y;
    if( gCalibImageNum == 0 )        gCalibImageNum = CALIB_IMAGE_NUM;
    if( gChessboardSquareWidth == 0.0f )       gChessboardSquareWidth = (float)CHESSBOARD_PATTERN_WIDTH;
    ARLOGi("CHESSBOARD_CORNER_NUM_X = %d\n", gChessboardCornerNumX);
    ARLOGi("CHESSBOARD_CORNER_NUM_Y = %d\n", gChessboardCornerNumY);
    ARLOGi("CHESSBOARD_PATTERN_WIDTH = %f\n", gChessboardSquareWidth);
    ARLOGi("CALIB_IMAGE_NUM = %d\n", gCalibImageNum);
    
    // Calibration inputs.
    arMalloc(gCornerSet, CvPoint2D32f, gChessboardCornerNumX*gChessboardCornerNumY*gCalibImageNum);
    
    // Library setup.
    int contextsActiveCount = 1;
    EdenMessageInit(contextsActiveCount);
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self start];
}

// On iOS 6.0 and later, we must explicitly report which orientations this view controller supports.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
#ifdef DEBUG_NO_INTERFACE_AUTOROTATION
    return UIInterfaceOrientationMaskPortrait;
#else
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSettingForceLandscapeStr])
        return UIInterfaceOrientationMaskLandscapeLeft;
    else return UIInterfaceOrientationMaskAll;
#endif
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                duration:(NSTimeInterval)duration
{
    BOOL wasRunning = running;
    if (wasRunning) [self stop];
    gDisplayOrientation = [self getDisplayOrientation:toInterfaceOrientation]; //TODO: Unnecessary?
    if (wasRunning) [self start];
}


- (void)startRunLoop
{
    if (!running) {
        // After starting the video, new frames will invoke cameraVideoTookPicture:userData:.
        if (ar2VideoCapStart(gVid) != 0) {
            NSLog(@"Error: Unable to begin camera data capture.\n");
            [self stop];
            return;
        }
        running = TRUE;
    }
}

- (void)stopRunLoop
{
    if (running) {
        ar2VideoCapStop(gVid);
        running = FALSE;
    }
}

- (void) setRunLoopInterval:(NSInteger)interval
{
    if (interval >= 1) {
        runLoopInterval = interval;
        if (running) {
            [self stopRunLoop];
            [self startRunLoop];
        }
    }
}

- (BOOL) isPaused
{
    if (!running) return (NO);

    return (videoPaused);
}

- (void) setPaused:(BOOL)paused
{
    if (!running) return;
    
    if (videoPaused != paused) {
        if (paused) ar2VideoCapStop(gVid);
        else ar2VideoCapStart(gVid);
        videoPaused = paused;
#  ifdef DEBUG
        NSLog(@"Run loop was %s.\n", (paused ? "PAUSED" : "UNPAUSED"));
#  endif
    }
}

static void startCallback(void *userData);

- (IBAction)start
{
    NSString *vconf = @"";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *preset, *position;
    if ([defaults objectForKey:kSettingCameraResolutionStr] == nil) preset = @"";
    else preset = [defaults objectForKey:kSettingCameraResolutionStr];
    if ([defaults objectForKey:kSettingCameraSourceStr] == nil) position = @"";
    else {
        position = [defaults objectForKey:kSettingCameraSourceStr];
        if ([position isEqualToString:kCameraSourceFront]) position = @"front";
        if ([position isEqualToString:kCameraSourceRear]) position = @"rear";
    }
    // Get start time.
    gettimeofday(&gStartTime, NULL);

    // Open the video path.
    // See http://www.artoolworks.com/support/library/Configuring_video_capture_in_ARToolKit_Professional#AR_VIDEO_DEVICE_IPHONE
    
    if (![preset isEqualToString:@""]) {
        preset = [NSString stringWithFormat:@"-preset=%@", preset];
        vconf = [NSString stringWithFormat:@"%@%@ ", vconf, preset];
    }
    if (![position isEqualToString:@""]) {
        position = [NSString stringWithFormat:@"-position=%@", position];
        vconf = [NSString stringWithFormat:@"%@%@ ", vconf, position];
    }
    
    if (!(gVid = ar2VideoOpenAsync([vconf UTF8String], startCallback, (__bridge void *)(self)))) {
        NSLog(@"Error: Unable to open connection to camera.\n");
        [self stop];
        return;
    }
}

static void startCallback(void *userData)
{
    ARViewController *vc = (ARViewController *)userData;
    
    [vc start2];
}

- (void) start2
{
    // Find the size of the window.
    int xsize, ysize;
    if (ar2VideoGetSize(gVid, &xsize, &ysize) < 0) {
        NSLog(@"Error: ar2VideoGetSize.\n");
        [self stop];
        return;
    }
    gVideoWidth = xsize;
    gVideoHeight = ysize;
    [ARViewController displayToastWithMessage:[NSString stringWithFormat:@"Camera: %dx%d", xsize, ysize]];
    
    // Get the format in which the camera is returning pixels.
    AR_PIXEL_FORMAT pixFormat = ar2VideoGetPixelFormat(gVid);
    if (pixFormat == AR_PIXEL_FORMAT_INVALID) {
        NSLog(@"Error: Camera is using unsupported pixel format.\n");
        [self stop];
        return;
    }
    
    UIInterfaceOrientation interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    gDisplayOrientation = [self getDisplayOrientation:interfaceOrientation];
    
    int frontCamera;
    gCameraIndex = 0;
    if (ar2VideoGetParami(gVid, AR_VIDEO_PARAM_IOS_CAMERA_POSITION, &frontCamera) >= 0) {
        gCameraIsFrontFacing = (frontCamera == AR_VIDEO_IOS_CAMERA_POSITION_FRONT);
        gCameraIndex = (gCameraIsFrontFacing ? 1 : 0);
    }

    // libARvideo on iPhone uses an underlying class called CameraVideo. Here, we
    // access the instance of this class to get/set some special types of information.
    CameraVideo *cameraVideo = ar2VideoGetNativeVideoInstanceiPhone(gVid->device.iPhone);
    if (!cameraVideo) {
        NSLog(@"Error: Unable to set up AR camera: missing CameraVideo instance.\n");
        [self stop];
        return;
    }
    
    // The camera will be started by -startRunLoop.
    [cameraVideo setTookPictureDelegate:self];
    [cameraVideo setTookPictureDelegateUserData:NULL];
    
    // Allocate the OpenGL view.
    glView = [[[ARView alloc] initWithFrame:[[UIScreen mainScreen] bounds] pixelFormat:kEAGLColorFormatRGBA8 depthFormat:kEAGLDepth16 withStencil:NO preserveBackbuffer:NO] autorelease]; // Don't retain it, as it will be retained when added to self.view.
    [glView setCameraPose:NULL];
    glView.arViewController = self;
    [self.view addSubview:glView];
    
    // Extra view setup.
    [glView addSubview:self.overlays];
    glView.touchDelegate = self;
    [glView addSubview:focusView];
    
    bool contentRotate90, contentFlipV, contentFlipH;
    // TODO: iPad - Different flips for different orientations
    if (gDisplayOrientation == 1) { // Landscape with top of device at left.
        contentRotate90 = false;
        contentFlipV = gCameraIsFrontFacing;
        contentFlipH = gCameraIsFrontFacing;
    } else if (gDisplayOrientation == 2) { // Portrait upside-down.
        contentRotate90 = true;
        contentFlipV = !gCameraIsFrontFacing;
        contentFlipH = true;
    } else if (gDisplayOrientation == 3) { // Landscape with top of device at right.
        contentRotate90 = false;
        contentFlipV = !gCameraIsFrontFacing;
        contentFlipH = (!gCameraIsFrontFacing);
    } else /*(gDisplayOrientation == 0)*/ { // Portait
        contentRotate90 = true;
        contentFlipV = gCameraIsFrontFacing;
        contentFlipH = false;
    }

    // Set up content positioning.
    glView.contentScaleMode = ARViewContentScaleModeFit;
    glView.contentAlignMode = ARViewContentAlignModeCenter;
    glView.contentWidth = xsize;
    glView.contentHeight = ysize;
    glView.contentRotate90 = contentRotate90;
    glView.contentFlipV = contentFlipV;
    glView.contentFlipH = contentFlipH;
#ifdef DEBUG
    NSLog(@"[ARViewController start] content %dx%d (wxh) will display in GL context %dx%d%s.\n", glView.contentWidth, glView.contentHeight, (int)glView.surfaceSize.width, (int)glView.surfaceSize.height, (glView.contentRotate90 ? " rotated" : ""));
#endif
    
    ARParam idealParam;
    if (arParamClear(&idealParam, xsize, ysize, AR_DIST_FUNCTION_VERSION_DEFAULT) < 0) {
        ARLOGe("Unable to create ARParam.\n");
        [self stop];
        return;
    }
    
    // Setup a route for rendering the colour background image.
    if ((gArglSettings = arglSetupForCurrentContext(&idealParam, pixFormat)) == NULL) {
        ARLOGe("Unable to setup argl.\n");
        [self stop];
        return;
    }
    if (!arglDistortionCompensationSet(gArglSettings, FALSE)) {
        ARLOGe("Unable to setup argl.\n");
        [self stop];
        return;
    }
    arglSetRotate90(gArglSettings, contentRotate90);
    arglSetFlipV(gArglSettings, contentFlipV);
    arglSetFlipH(gArglSettings, contentFlipH);

    // Setup a route for rendering the mono background image.
    if ((gArglSettingsCornerFinderImage = arglSetupForCurrentContext(&idealParam, AR_PIXEL_FORMAT_MONO)) == NULL) {
        ARLOGe("Unable to setup argl.\n");
        [self stop];
        return;
    }
    if (!arglDistortionCompensationSet(gArglSettingsCornerFinderImage, FALSE)) {
        ARLOGe("Unable to setup argl.\n");
        [self stop];
        return;
    }
    arglSetRotate90(gArglSettingsCornerFinderImage, contentRotate90);
    arglSetFlipV(gArglSettingsCornerFinderImage, contentFlipV);
    arglSetFlipH(gArglSettingsCornerFinderImage, contentFlipH);
    
    //
    // Calibration init.
    //
    
    //
    // Corner finder inputs and outputs.
    //
    CORNER_FINDER_DATA_T* cornerFinderDataPtr;
    arMallocClear(cornerFinderDataPtr, CORNER_FINDER_DATA_T, 1);
    cornerFinderDataPtr->chessboardCornerNumX = gChessboardCornerNumX;
    cornerFinderDataPtr->chessboardCornerNumY = gChessboardCornerNumY;
    arMalloc(cornerFinderDataPtr->corners, CvPoint2D32f, cornerFinderDataPtr->chessboardCornerNumX * cornerFinderDataPtr->chessboardCornerNumY);
    arMalloc(cornerFinderDataPtr->videoFrame, ARUint8, xsize*ysize);
    cornerFinderDataPtr->calibImage = cvCreateImageHeader(cvSize(xsize, ysize), IPL_DEPTH_8U, 1);
    cvSetData(cornerFinderDataPtr->calibImage, cornerFinderDataPtr->videoFrame, xsize); // Last parameter is rowBytes.
    
    // Spawn the corner finder worker thread.
    cornerFinderThread = threadInit(0, (void*)(cornerFinderDataPtr), cornerFinder);
    
    // Corner finder results copy, for display to user.
    arMalloc(gCorners, CvPoint2D32f, gChessboardCornerNumX*gChessboardCornerNumY);
    arMalloc(gCornerFinderImage, ARUint8, xsize*ysize);
    pthread_mutex_init(&gCornerFinderResultLock, NULL);

    if (!flowInitAndStart(gCalibImageNum)) {
        ARLOGe("Error: Could not initialise and start flow.\n");
        exit(-1);
    }
    
    // For FPS statistics.
    arUtilTimerReset();
    gCallCountMarkerDetect = 0;
    
    //Create our runloop timer
    [self setRunLoopInterval:2]; // Target 30 fps on a 60 fps device.
    [self startRunLoop];
}

- (int) getDisplayOrientation:(int) interfaceOrientation {
    int orientInt;
    switch (interfaceOrientation) {
        case UIDeviceOrientationLandscapeLeft:
            orientInt = 1;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientInt = 2;
            break;
        case UIDeviceOrientationLandscapeRight:
            orientInt = 3;
            break;
        case UIDeviceOrientationPortrait:
            orientInt = 0;
            break;
        case UIDeviceOrientationUnknown:
            orientInt = 0;
            break;
        default:
            orientInt = 0;
            break;
    }
    return orientInt;
}

- (void) cameraVideoTookPicture:(id)sender userData:(void *)data
{
    AR2VideoBufferT *buffer = ar2VideoGetImage(gVid);
    if (buffer) [self processFrame:buffer];
}

- (void) processFrame:(AR2VideoBufferT *)buffer
{
    int i;
    
    if (buffer) {
        gCallCountMarkerDetect++; // Increment ARToolKit FPS counter.
#ifdef DEBUG
        //NSLog(@"video frame %ld.\n", gCallCountMarkerDetect);
#endif
#ifdef DEBUG
        if (gCallCountMarkerDetect % 150 == 0) {
            NSLog(@"*** Camera - %f (frame/sec)\n", (double)gCallCountMarkerDetect/arUtilTimer());
            gCallCountMarkerDetect = 0;
            arUtilTimerReset();
        }
#endif

        FLOW_STATE state = flowStateGet();
        if (state == FLOW_STATE_WELCOME || state == FLOW_STATE_DONE || state == FLOW_STATE_CALIBRATING) {
            
            // Upload the frame to OpenGL.
            if (buffer->bufPlaneCount == 2) arglPixelBufferDataUploadBiPlanar(gArglSettings, buffer->bufPlanes[0], buffer->bufPlanes[1]);
            else arglPixelBufferDataUpload(gArglSettings, buffer->buff);
            
        } else if (state == FLOW_STATE_CAPTURING) {
            //
            // Start of main calibration-related cycle.
            //
            
            // First, see if an image has been completely processed.
            if (threadGetStatus(cornerFinderThread)) {
                threadEndWait(cornerFinderThread); // We know from status above that worker has already finished, so this just resets it.
                ARLOGd("processFrame: corner find DONE.\n");
                
                // Copy the results.
                pthread_mutex_lock(&gCornerFinderResultLock); // Results are also read by GL thread, so need to lock before modifying.
                CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(cornerFinderThread);
                gCornerFlag = cornerFinderData->cornerFlag;
                gCornerCount = cornerFinderData->cornerCount;
                for (i = 0; i < cornerFinderData->chessboardCornerNumX*cornerFinderData->chessboardCornerNumY; i++) gCorners[i] = cornerFinderData->corners[i];
                memcpy(gCornerFinderImage, cornerFinderData->videoFrame, gVideoWidth*gVideoHeight); // For the visual overlay of corner locations to be accurate, we need a copy of the image in which they were found.
                arglPixelBufferDataUpload(gArglSettingsCornerFinderImage, gCornerFinderImage);
                pthread_mutex_unlock(&gCornerFinderResultLock);
            }
            
            // If corner finder worker thread is ready and waiting, submit the new image.
            if (!threadGetBusyStatus(cornerFinderThread)) {
                ARLOGd("processFrame: corner find GO\n");

                // As corner finding takes longer than a single frame capture, we need to copy the incoming image
                // so that OpenCV has exclusive use of it. We copy into cornerFinderData->videoFrame which provides
                // the backing for calibImage.
                CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(cornerFinderThread);
                memcpy(cornerFinderData->videoFrame, buffer->buffLuma, gVideoWidth*gVideoHeight);
                
                // Kick off a new cycle of the cornerFinder. The results will be collected on a subsequent cycle.
                threadStartSignal(cornerFinderThread);
            }
            
            //
            // End of main calibration-related cycle.
            //
        }

        // Get current time (units = seconds).
        NSTimeInterval runLoopTimeNow;
        runLoopTimeNow = CFAbsoluteTimeGetCurrent();
        //[glView updateWithTimeDelta:(runLoopTimeNow - runLoopTimePrevious)];
        
        // The display has changed.
        [glView drawView:self];
        
        // Save timestamp for next loop.
        runLoopTimePrevious = runLoopTimeNow;
    }

}

- (BOOL)cornerFinderResultsLockAndFetchCornerFlag:(int *)cornerFlag cornerCount:(int *)cornerCount corners:(CvPoint2D32f **)corners
{
    pthread_mutex_lock(&gCornerFinderResultLock);
    *cornerFlag = gCornerFlag;
    *cornerCount = gCornerCount;
    *corners = gCorners;
    return TRUE;
}

- (BOOL)cornerFinderResultsUnlock
{
    pthread_mutex_unlock(&gCornerFinderResultLock);
    return TRUE;
}

// Worker thread.
static void *cornerFinder(THREAD_HANDLE_T *threadHandle)
{
#ifdef DEBUG
    ARLOGi("Start cornerFinder thread.\n");
#endif
    
    CORNER_FINDER_DATA_T  *cornerFinderDataPtr = (CORNER_FINDER_DATA_T *)threadGetArg(threadHandle);
    
    while (threadStartWait(threadHandle) == 0) {
        
        cornerFinderDataPtr->cornerFlag = cvFindChessboardCorners(cornerFinderDataPtr->calibImage,
                                                                  cvSize(cornerFinderDataPtr->chessboardCornerNumY, cornerFinderDataPtr->chessboardCornerNumX),
                                                                  cornerFinderDataPtr->corners,
                                                                  &(cornerFinderDataPtr->cornerCount),
                                                                  CV_CALIB_CB_FAST_CHECK|CV_CALIB_CB_ADAPTIVE_THRESH|CV_CALIB_CB_FILTER_QUADS);
        threadEndSignal(threadHandle);
    }
    
#ifdef DEBUG
    ARLOGi("End cornerFinder thread.\n");
#endif
    return (NULL);
}

- (IBAction)stop
{
    [self stopRunLoop];
    
    // Stop calibration flow.
    flowStopAndFinal();
    
    // Clean up results copy.
    // Free space for results.
    if (gCorners) {
        free(gCorners);
        gCorners = NULL;
    }
    gCornerCount = 0;
    gCornerFlag = 0;
    if (gCornerFinderImage) {
        free(gCornerFinderImage);
        gCornerFinderImage = NULL;
    }
    pthread_mutex_destroy(&gCornerFinderResultLock);
    
    // Clean up the corner finder.
    if (cornerFinderThread) {
        
        threadWaitQuit(cornerFinderThread);
        CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(cornerFinderThread);
        
        if (cornerFinderData->calibImage) cvReleaseImageHeader(&(cornerFinderData->calibImage));
        free(cornerFinderData->videoFrame);
        
        // Free space for results.
        if (cornerFinderData->corners) {
            free(cornerFinderData->corners);
            cornerFinderData->corners = NULL;
        }
        cornerFinderData->cornerCount = 0;
        cornerFinderData->cornerFlag = 0;
        threadFree(&cornerFinderThread);
    }
    
    if (gArglSettings) {
        arglCleanup(gArglSettings); // Clean up any left-over ARGL data.
        gArglSettings = NULL;
    }
    if (gArglSettingsCornerFinderImage) {
        arglCleanup(gArglSettingsCornerFinderImage); // Clean up any left-over ARGL data.
        gArglSettingsCornerFinderImage = NULL;
    }
    
    [overlays removeFromSuperview];
    [glView removeFromSuperview]; // Will result in glView being released.
    glView = nil;
    [focusView removeFromSuperview];
    
    if (gVid) {
        ar2VideoClose(gVid);
        gVid = NULL;
    }
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

- (void)viewWillDisappear:(BOOL)animated {
    [self stop];
    
    [super viewWillDisappear:animated];
}

- (void)dealloc {
    EdenMessageFinal();
    
    // Calibration input cleanup.
    free(gCornerSet);
    gCornerSet = NULL;
    
    fileUploaderFinal(&fileUploadHandle);
    
    if (focusView) {
        [focusView release];
        focusView = nil;
    }
    
    [super dealloc];
}

// Call this method to take a snapshot of the ARView.
// Once the image is ready, tookSnapshot:forview: will be called.
- (void)takeSnapshot
{
    // We will need to wait for OpenGL rendering to complete.
    [glView setTookSnapshotDelegate:self];
    [glView takeSnapshot];
}

// Here you can choose what to do with the image.
// We will save it to the iOS camera roll.
- (void)tookSnapshot:(UIImage *)snapshot forView:(EAGLView *)view
{
    // First though, unset ourselves as delegate.
    [glView setTookSnapshotDelegate:nil];
    
    // Write image to camera roll.
    UIImageWriteToSavedPhotosAlbum(snapshot, self, @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

// Let the user know that the image was saved by playing a shutter sound,
// or if there was an error, put up an alert.
- (void) image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (!error) {
        SystemSoundID shutterSound;
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource: @"slr_camera_shutter" withExtension: @"wav"], &shutterSound);
        AudioServicesPlaySystemSound(shutterSound);
    } else {
        NSString *titleString = @"Error saving screenshot";
        NSString *messageString = [error localizedDescription];
        NSString *moreString = [error localizedFailureReason] ? [error localizedFailureReason] : NSLocalizedString(@"Please try again.", nil);
        messageString = [NSString stringWithFormat:@"%@. %@", messageString, moreString];
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:titleString message:messageString delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
        //ARC
        //[alertView release];
    }
}

- (void) handleTouchAtLocation:(CGPoint)location tapCount:(NSUInteger)tapCount
{
    // Convert touch coordinates to a location in the OpenGL viewport.
    CGPoint locationInViewportCoords = CGPointMake(location.x * (float)glView.backingWidth/glView.surfaceSize.width - glView.viewPort[viewPortIndexLeft], (glView.surfaceSize.height - location.y) * (float)glView.backingHeight/glView.surfaceSize.height - glView.viewPort[viewPortIndexBottom]);

    // Now work out where that is in the OpenGL ortho2D frustum.
    int contentWidthFinalOrientation = (glView.contentRotate90 ? glView.contentHeight : glView.contentWidth);
    int contentHeightFinalOrientation = (glView.contentRotate90 ? glView.contentWidth : glView.contentHeight);
    float viewPortScaleFactorWidth = (float)glView.viewPort[viewPortIndexWidth] / (float)contentWidthFinalOrientation;
    float viewPortScaleFactorHeight = (float)glView.viewPort[viewPortIndexHeight] / (float)contentHeightFinalOrientation;
    CGPoint locationInOrtho2DCoords = CGPointMake(locationInViewportCoords.x / viewPortScaleFactorWidth, locationInViewportCoords.y / viewPortScaleFactorHeight);
    
    // Now reverse the transformations we used to fit the content into the ortho2D frustum.
    if (glView.contentRotate90) locationInOrtho2DCoords = CGPointMake(glView.contentWidth - locationInOrtho2DCoords.y, locationInOrtho2DCoords.x);
    if (glView.contentFlipH) locationInOrtho2DCoords = CGPointMake(glView.contentWidth - locationInOrtho2DCoords.x, locationInOrtho2DCoords.y);
    if (glView.contentFlipV) locationInOrtho2DCoords = CGPointMake(locationInOrtho2DCoords.x, glView.contentHeight - locationInOrtho2DCoords.y);
    
    // (0, 0) is top-left of frame.
    CGPoint locationInContentCoords = CGPointMake(locationInOrtho2DCoords.x, glView.contentHeight - locationInOrtho2DCoords.y);
    
    // Now request a point-of-interest focus cycle.
    ar2VideoSetParamd(gVid, AR_VIDEO_FOCUS_POINT_OF_INTEREST_X, locationInContentCoords.x);
    ar2VideoSetParamd(gVid, AR_VIDEO_FOCUS_POINT_OF_INTEREST_Y, locationInContentCoords.y);
    if (ar2VideoSetParami(gVid, AR_VIDEO_FOCUS_MODE, AR_VIDEO_FOCUS_MODE_POINT_OF_INTEREST) == 0) {
        // Show the focus indicator.
        [focusView updatePoint:location];
        [focusView animateFocusingAction];
    }
}

- (IBAction)handleCaptureButton:(id)sender
{
    flowHandleEvent(EVENT_TOUCH);
}

- (IBAction)handleBackButton:(id)sender
{
    flowHandleEvent(EVENT_BACK_BUTTON);
}

- (IBAction)showMenu:(id)sender {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self presentViewController:[[SettingsViewController alloc] init] animated:YES completion:nil]; }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Help" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://www.artoolworks.com/support/applink/calib_camera-android-help"]]; }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Print" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *pdfFileName;
        if ([[NSUserDefaults standardUserDefaults] objectForKey:kSettingPaperSizeStr] == nil)
            pdfFileName = [[NSUserDefaults standardUserDefaults] objectForKey:kSettingPaperSizeStr];
        else pdfFileName = kPaperSizeUSLetterStr;
        NSString *pdfPath;
        pdfPath = pdfFileName == kPaperSizeUSLetterStr ? [[NSBundle mainBundle] pathForResource:@"printusletter" ofType:@"pdf"] : [[NSBundle mainBundle] pathForResource:@"printa4" ofType:@"pdf"];
        NSLog(@"PDF path: %@", pdfPath);
        [self tryPrintPdf:pdfPath];
    }]];
    [alertController.popoverPresentationController setBarButtonItem:self.menuButtonItem];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void) tryPrintPdf:(NSString*)path {
    NSData *myData = [NSData dataWithContentsOfFile:path];
    UIPrintInteractionController *pic = [UIPrintInteractionController sharedPrintController];
    if ( pic && [UIPrintInteractionController canPrintData: myData] ) {
        pic.delegate = self;
        UIPrintInfo *printInfo = [UIPrintInfo printInfo];
        printInfo.outputType = UIPrintInfoOutputGeneral;
        printInfo.jobName = [path lastPathComponent];
        printInfo.duplex = UIPrintInfoDuplexLongEdge;
        pic.printInfo = printInfo;
        pic.showsPageRange = YES;
        pic.printingItem = myData;
        
        void (^completionHandler)(UIPrintInteractionController *, BOOL, NSError *) = ^(UIPrintInteractionController *pic, BOOL completed, NSError *error) {
            if (!completed && error) {
                NSLog(@"FAILED! due to error in domain %@ with error code %ld", error.domain, (long)error.code);
            }
        };
        
        [pic presentAnimated:YES completionHandler:completionHandler];
    }
}

// Called when user chooses "Done" from QuickLook.
- (void)documentInteractionControllerDidEndPreview:(UIDocumentInteractionController *)controller
{
    
}

+ (void)displayToastWithMessage:(NSString *)toastMessage
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        UIWindow * keyWindow = [[UIApplication sharedApplication] keyWindow];
        UILabel *toastView = [[UILabel alloc] init];
        toastView.text = toastMessage;
        toastView.font = [UIFont fontWithName:@"Helvetica" size:14.0f];
        toastView.textColor = [UIColor whiteColor];
        toastView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
        toastView.textAlignment = NSTextAlignmentCenter;
        toastView.frame = CGRectMake(0.0f, 0.0f, keyWindow.frame.size.width/2.0f, 28.0f);
        toastView.layer.cornerRadius = 7.0f;
        toastView.layer.masksToBounds = YES;
        toastView.center = keyWindow.center;
        
        [keyWindow addSubview:toastView];
        
        [UIView animateWithDuration: 3.0f
                              delay: 0.0
                            options: UIViewAnimationOptionCurveEaseOut
                         animations: ^{
                             toastView.alpha = 0.0;
                         }
                         completion: ^(BOOL finished) {
                             [toastView removeFromSuperview];
                         }
         ];
    }];
}

@end


bool capture(const int capturedImageNum)
{
    CORNER_FINDER_DATA_T *cornerFinderDataPtr;
    CvPoint2D32f   *p1, *p2;
    int             i;
    
    cornerFinderDataPtr = (CORNER_FINDER_DATA_T *)threadGetArg(cornerFinderThread);
    if( cornerFinderDataPtr->cornerFlag ) {
        cvFindCornerSubPix( cornerFinderDataPtr->calibImage,
                           cornerFinderDataPtr->corners,
                           cornerFinderDataPtr->chessboardCornerNumX*cornerFinderDataPtr->chessboardCornerNumY,
                           cvSize(5,5),
                           cvSize(-1,-1),
                           cvTermCriteria(CV_TERMCRIT_ITER, 100, 0.1)  );
        
        // Copy the corners.
        p1 = cornerFinderDataPtr->corners;
        p2 = &gCornerSet[capturedImageNum*gChessboardCornerNumX*gChessboardCornerNumY];
        for( i = 0; i < gChessboardCornerNumX*gChessboardCornerNumY; i++ ) {
            *(p2++) = *(p1++);
        }
        
        ARLOG("---------- %2d/%2d -----------\n", capturedImageNum + 1, gCalibImageNum);
        for (i = 0; i < gChessboardCornerNumX*gChessboardCornerNumY; i++) {
            ARLOG("  %f, %f\n", gCornerSet[capturedImageNum*gChessboardCornerNumX*gChessboardCornerNumY + i].x, gCornerSet[capturedImageNum*gChessboardCornerNumX*gChessboardCornerNumY + i].y);
        }
        ARLOG("---------- %2d/%2d -----------\n", capturedImageNum + 1, gCalibImageNum);
        
        return (true);
    } else {
        return (false);
    }
}

void calib(ARParam *param_out, ARdouble *err_min_out, ARdouble *err_avg_out, ARdouble *err_max_out)
{
    calc(gCalibImageNum, gChessboardCornerNumX, gChessboardCornerNumY, gChessboardSquareWidth, gCornerSet, gVideoWidth, gVideoHeight, param_out, err_min_out, err_avg_out, err_max_out);
}



// Save parameters file and index file with info about it, then signal thread that it's ready for upload.
void saveParam(const ARParam *param, ARdouble err_min, ARdouble err_avg, ARdouble err_max)
{
    int i;
#define SAVEPARAM_PATHNAME_LEN 80
    char indexPathname[SAVEPARAM_PATHNAME_LEN];
    char paramPathname[SAVEPARAM_PATHNAME_LEN];
    char indexUploadPathname[SAVEPARAM_PATHNAME_LEN];
    
    // Get the current time. It will be used for file IDs, plus a timestamp for the parameters file.
    time_t ourClock = time(NULL);
    if (ourClock == (time_t)-1) {
        ARLOGe("Error reading time and date.\n");
        return;
    }
    //struct tm *timeptr = localtime(&ourClock);
    struct tm *timeptr = gmtime(&ourClock);
    if (!timeptr) {
        ARLOGe("Error converting time and date to UTC.\n");
        return;
    }
    int ID = timeptr->tm_hour*10000 + timeptr->tm_min*100 + timeptr->tm_sec;
    
    // Check for QUEUE_DIR and create if not already existing.
    if (!fileUploaderCreateQueueDir(fileUploadHandle)) {
    //if (![self createQueueDir(QUEUE_DIR)])
        return;
    }
    
    // Save the parameter file.
    snprintf(paramPathname, SAVEPARAM_PATHNAME_LEN, "%s/%06d-camera_para.dat", QUEUE_DIR, ID);
    
    //if (arParamSave(strcat(strcat(docsPath,"/"),paramPathname), 1, param) < 0) {
    if (arParamSave(paramPathname, 1, param) < 0) {
        
        ARLOGe("Error writing camera_para.dat file.\n");
        
    } else {
        
        //
        // Write an upload index file with the data for the server database entry.
        //
        
        bool goodWrite = true;
        
        // Open the file.
        snprintf(indexPathname, SAVEPARAM_PATHNAME_LEN, "%s/%06d-index", QUEUE_DIR, ID);
        FILE *fp;
        if (!(fp = fopen(indexPathname, "wb"))) {
            ARLOGe("Error opening upload index file '%s'.\n", indexPathname);
            goodWrite = false;
        }
        
        // File name.
        if (goodWrite) fprintf(fp, "file,%s\n", paramPathname);
        
        // UTC date and time, in format "1999-12-31 23:59:59 UTC".
        if (goodWrite) {
            char timestamp[26+8] = "";
            if (!strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S %z", timeptr)) {
                ARLOGe("Error formatting time and date.\n");
                goodWrite = false;
            } else {
                fprintf(fp, "timestamp,%s\n", timestamp);
            }
        }
        
        // OS: name/arch/version.
        if (goodWrite) {
            fprintf(fp, "os_name,ios\n");
            fprintf(fp, "os_arch,%s\n", cpuTypeName());
            NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
            fprintf(fp, "os_version,%s\n", [currSysVer UTF8String]);
        }
        
        // Handset ID.
        if (goodWrite) {
            NSString *deviceType = [UIDevice currentDevice].model;
            char *machine = arUtilGetMachineType();
            fprintf(fp, "device_id,apple/%s/%s\n", [deviceType UTF8String], machine);
            free(machine);
        }
        
        // Focal length in metres.
        // Not known at present, so just send 0.000.
        if (goodWrite) {
            char focal_length[] = "0.000";
            fprintf(fp, "focal_length,%s\n", focal_length);
        }
        
        // Camera index.
        if (goodWrite) {
            char camera_index[12]; // 10 digits in INT32_MAX, plus sign, plus null.
            snprintf(camera_index, 12, "%d", gCameraIndex);
            fprintf(fp, "camera_index,%s\n", camera_index);
        }
        
        // Front or rear facing.
        if (goodWrite) {
            char camera_face[6]; // "front" or "rear", plus null.
            snprintf(camera_face, 6, "%s", (gCameraIsFrontFacing ? "front" : "rear"));
            fprintf(fp, "camera_face,%s\n", camera_face);
        }
        
        // Camera dimensions.
        if (goodWrite) {
            char camera_width[12]; // 10 digits in INT32_MAX, plus sign, plus null.
            char camera_height[12]; // 10 digits in INT32_MAX, plus sign, plus null.
            snprintf(camera_width, 12, "%d", gVideoWidth);
            snprintf(camera_height, 12, "%d", gVideoHeight);
            fprintf(fp, "camera_width,%s\n", camera_width);
            fprintf(fp, "camera_height,%s\n", camera_height);
        }
        
        // Calibration error.
        if (goodWrite) {
            char err_min_ascii[12];
            char err_avg_ascii[12];
            char err_max_ascii[12];
            snprintf(err_min_ascii, 12, "%f", err_min);
            snprintf(err_avg_ascii, 12, "%f", err_avg);
            snprintf(err_max_ascii, 12, "%f", err_max);
            fprintf(fp, "err_min,%s\n", err_min_ascii);
            fprintf(fp, "err_avg,%s\n", err_avg_ascii);
            fprintf(fp, "err_max,%s\n", err_max_ascii);
        }
        
        // IP address will be derived from connect.
        
        // Hash the shared secret.
        if (goodWrite) {
            //char ss[] = SHARED_SECRET;
            unsigned char ss_md5[MD5_DIGEST_LENGTH] = SHARED_SECRET_MD5;
            char ss_ascii[MD5_DIGEST_LENGTH*2 + 1]; // space for null terminator.
            //if (!MD5((unsigned char *)ss, strlen(ss), ss_md5)) {
            //	ARLOGe("Error calculating md5.\n");
            //	goto done;
            //}
            for (i = 0; i < MD5_DIGEST_LENGTH; i++) snprintf(&(ss_ascii[i*2]), 3, "%.2hhx", ss_md5[i]);
            fprintf(fp, "ss,%s\n", ss_ascii);
        }
        
        // Done writing index file.
        fclose(fp);
        
        if (goodWrite) {
            // Rename the file with QUEUE_INDEX_FILE_EXTENSION file extension so it's picked up in uploader.
            snprintf(indexUploadPathname, SAVEPARAM_PATHNAME_LEN, "%s.upload", indexPathname);
            if (rename(indexPathname, indexUploadPathname) < 0) {
                ARLOGe("Error renaming temporary file '%s'.\n", indexPathname);
                goodWrite = false;
            } else {
                // Kick off an upload handling cycle.
                fileUploaderTickle(fileUploadHandle);
            }
        }
        
        if (!goodWrite) {
            // Delete the index and param files.
            if (remove(indexPathname) < 0) {
                ARLOGe("Error removing temporary file '%s'.\n", indexPathname);
                ARLOGperror(NULL);
            }
            if (remove(paramPathname) < 0) {
                ARLOGe("Error removing temporary file '%s'.\n", paramPathname);
                ARLOGperror(NULL);
            }
        }
    }
}
