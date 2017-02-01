/*
 *  calib_camera.cpp
 *  ARToolKit6
 *
 *  Camera calibration utility.
 *
 *  Run with "--help" parameter to see usage.
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
 *  Copyright 2015-2016 Daqri, LLC.
 *  Copyright 2002-2015 ARToolworks, Inc.
 *
 *  Author(s): Hirokazu Kato, Philip Lamb
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#ifdef _WIN32
#  include <windows.h>
#  define MAXPATHLEN MAX_PATH
#  include <direct.h> // getcwd
#else
#  include <sys/param.h> // MAXPATHLEN
#  include <unistd.h> // getcwd
#endif
#ifdef __APPLE__
#  include <OpenGL/gl.h>
#elif defined(__linux) || defined(_WIN32)
#  include <GL/gl.h>
#endif
#include <opencv2/calib3d.hpp>
#include <opencv2/imgproc/imgproc_c.h>
#include <AR6/AR/ar.h>
//#include <AR6/ARVideo/video.h>
#include <AR6/ARVideoSource.h>
#include <AR6/ARView.h>
#include <AR6/ARUtil/system.h>
#include <AR6/ARUtil/thread_sub.h>
#include <AR6/ARUtil/time.h>
#include <AR6/ARG/arg.h>

#include <SDL2/SDL.h>

#include "fileUploader.h"
#include "calc.h"
#include "flow.h"
#include "Eden/EdenMessage.h"
#include "Eden/EdenGLFont.h"

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

#ifdef __APPLE__
#  include <CommonCrypto/CommonDigest.h>
#  define MD5 CC_MD5
#  define MD5_DIGEST_LENGTH CC_MD5_DIGEST_LENGTH
#else
//#include <openssl/md5.h>
// Rather than including full OpenSSL header tree, just provide prototype for MD5().
// Usage is here: http://www.openssl.org/docs/crypto/md5.html.
#  define MD5_DIGEST_LENGTH 16
#  ifdef __cplusplus
extern "C" {
#  endif
unsigned char *MD5(const unsigned char *d, size_t n, unsigned char *md);
#  ifdef __cplusplus
}
#  endif
#endif

// Until we implement nonce-based hashing, use of the plain md5 of the shared secret is vulnerable to replay attack.
// The shared secret itself needs to be hidden in the binary.
#define SHARED_SECRET "com.artoolworks.utils.calib_camera.116D5A95-E17B-266E-39E4-E5DED6C07C53" // SHARED_SECRET_MD5 = {0x32, 0x57, 0x5a, 0x6f, 0x69, 0xa4, 0x11, 0x5a, 0x25, 0x49, 0xae, 0x55, 0x6b, 0xd2, 0x2a, 0xda}

#define VCONF ""

#define FONT_SIZE 6.8f

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
//static int                  gVideoWidth = 0;
//static int                  gVideoHeight = 0;


//
// Data upload.
//

FILE_UPLOAD_HANDLE_t *fileUploadHandle = NULL;

// Video acquisition and rendering.
//AR2VideoParamT *gVid = NULL;
ARVideoSource *vs = nullptr;
ARView *vv = nullptr;


// Marker detection.
long            gCallCountMarkerDetect = 0;

// Window and GL context.
static SDL_GLContext gSDLContext = NULL;
static int contextWidth = 0;
static int contextHeight = 0;
static bool contextWasUpdated = false;
static SDL_Window* gSDLWindow = NULL;
static int32_t gViewport[4] = {0, 0, 0, 0}; // {x, y, width, height}
//static ARGL_CONTEXT_SETTINGS_REF gArglSettings = NULL;
static int gDisplayOrientation = 0; // range [0-3]. 1=landscape.
static float gDisplayDPI = 72.0f;

// Main state.
static struct timeval gStartTime;

//
// Calibration.
//

// Corner finder results copy, for display to user.
static ARGL_CONTEXT_SETTINGS_REF gArglSettingsCornerFinderImage = NULL;;
static ARUint8*             gCornerFinderImage = NULL;; // The image to which gCorners apply.
static pthread_mutex_t      gCornerFinderResultLock;
static int                  gCornerFlag = 0;
static int                  gCornerCount = 0;
static CvPoint2D32f        *gCorners = NULL;

// ============================================================================
//	Function prototypes
// ============================================================================

static void *cornerFinder(THREAD_HANDLE_T *threadHandle);
static void start2(void *userData);
static void processFrame(void *userData);
static void mainLoop(void);
static void quit(int rc);
static void reshape(int w, int h);
static void drawView(void);






//AR_PIXEL_FORMAT      pixFormat;
//int                  xsize;
//int                  ysize;
//ARUint8             *imageLumaCopy        = NULL;
//IplImage            *calibImage           = NULL;
//int                  chessboardCornerNumX = 0;
//int                  chessboardCornerNumY = 0;
//int                  calibImageNum        = 0;
//int                  capturedImageNum     = 0;
//float                patternWidth         = 0.0f;
//int                  cornerFlag           = 0;

static void          init(int argc, char *argv[]);
static void          usage(char *com);
static void          cleanup(void);
static void          mainLoop(void);


int main(int argc, char *argv[])
{
    // Initialize SDL.
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        ARLOGe("Error: SDL initialisation failed. SDL error: '%s'.\n", SDL_GetError());
        return -1;
    }
    
    // Create a window.
    gSDLWindow = SDL_CreateWindow("ARToolKit6 Camera Calibration Utility",
                                  SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                  1280, 720,
                                  SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI
                                  );
    if (!gSDLWindow) {
        ARLOGe("Error creating window: %s.\n", SDL_GetError());
        quit(-1);
    }
    
    // Create an OpenGL context to draw into.
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 1);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 5);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1); // This is the default.
    SDL_GL_SetSwapInterval(1);
    gSDLContext = SDL_GL_CreateContext(gSDLWindow);
    if (!gSDLContext) {
        ARLOGe("Error creating OpenGL context: %s.\n", SDL_GetError());
        return -1;
    }
    int w, h;
    SDL_GL_GetDrawableSize(SDL_GL_GetCurrentWindow(), &w, &h);
    reshape(w, h);
    
    
    char *queuePath = NULL;
    asprintf(&queuePath, "%s/%s", arUtilGetResourcesDirectoryPath(AR_UTIL_RESOURCES_DIRECTORY_BEHAVIOR_USE_APP_CACHE_DIR), QUEUE_DIR);
    fileUploadHandle = fileUploaderInit(queuePath, QUEUE_INDEX_FILE_EXTENSION, UPLOAD_POST_URL, UPLOAD_STATUS_HIDE_AFTER_SECONDS);
    if (!fileUploadHandle) {
        ARLOGe("Error: Could not initialise fileUploadHandle.\n");
    }
    free(queuePath);
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
    
    // Get start time.
    gettimeofday(&gStartTime, NULL);
    
    vs = new ARVideoSource;
    if (!vs) {
        ARLOGe("Error: Unable to create video source.\n");
        quit(-1);
    }
    vs->configure(VCONF, true, NULL, NULL, 0);
    if (!vs->open()) {
        ARLOGe("Error: Unable to open video source.\n");
        quit(-1);
    }
    
    // Main loop.
    bool postVideoSetupDone = false;
    bool done = false;
    while (!done) {
        
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT /*|| (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_ESCAPE)*/) {
                done = true;
                break;
            } else if (ev.type == SDL_WINDOWEVENT) {
                //ARLOGd("Window event %d.\n", ev.window.event);
                if (ev.window.event == SDL_WINDOWEVENT_RESIZED && ev.window.windowID == SDL_GetWindowID(gSDLWindow)) {
                    //int32_t w = ev.window.data1;
                    //int32_t h = ev.window.data2;
                    int w, h;
                    SDL_GL_GetDrawableSize(gSDLWindow, &w, &h);
                    reshape(w, h);
                }
            } else if (ev.type == SDL_KEYDOWN) {
                if        (ev.key.keysym.sym == SDLK_ESCAPE) {
                    flowHandleEvent(EVENT_BACK_BUTTON);
                } else if (ev.key.keysym.sym == SDLK_SPACE) {
                    flowHandleEvent(EVENT_TOUCH);
                }
            }
        }
        
        if (vs->isOpen()) {
            if (!postVideoSetupDone) {
                
                // TODO: replace this with camera selection from source info list.
                gCameraIndex = 0;
                gCameraIsFrontFacing = false;
                //#if __APPLE__
                //                int frontCamera;
                //                if (ar2VideoGetParami(gVid, AR_VIDEO_PARAM_AVFOUNDATION_CAMERA_POSITION, &frontCamera) >= 0) {
                //                    gCameraIsFrontFacing = (frontCamera == AR_VIDEO_AVFOUNDATION_CAMERA_POSITION_FRONT);
                //                }
                //#endif
                bool contentRotate90, contentFlipV, contentFlipH;
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
                
                // Setup a route for rendering the colour background image.
                vv = new ARView;
                if (!vv) {
                    ARLOGe("Error: unable to create video view.\n");
                    quit(-1);
                }
                vv->setRotate90(contentRotate90);
                vv->setFlipH(contentFlipH);
                vv->setFlipV(contentFlipV);
                vv->setScalingMode(ARView::ScalingMode::SCALE_MODE_FIT);
                vv->initWithVideoSource(*vs, contextWidth, contextHeight);
#ifdef DEBUG
                ARLOGe("Content %dx%d (wxh) will display in GL context %dx%d%s.\n", vs->getVideoWidth(), vs->getVideoHeight(), contextWidth, contextHeight, (contentRotate90 ? " rotated" : ""));
#endif
                vv->getViewport(gViewport);
                
                // Setup a route for rendering the mono background image.
                ARParam idealParam;
                arParamClear(&idealParam, vs->getVideoWidth(), vs->getVideoHeight(), AR_DIST_FUNCTION_VERSION_DEFAULT);
                if ((gArglSettingsCornerFinderImage = arglSetupForCurrentContext(&idealParam, AR_PIXEL_FORMAT_MONO)) == NULL) {
                    ARLOGe("Unable to setup argl.\n");
                    quit(-1);
                }
                if (!arglDistortionCompensationSet(gArglSettingsCornerFinderImage, FALSE)) {
                    ARLOGe("Unable to setup argl.\n");
                    quit(-1);
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
                arMalloc(cornerFinderDataPtr->videoFrame, ARUint8, vs->getVideoWidth()*vs->getVideoHeight());
                cornerFinderDataPtr->calibImage = cvCreateImageHeader(cvSize(vs->getVideoWidth(), vs->getVideoHeight()), IPL_DEPTH_8U, 1);
                cvSetData(cornerFinderDataPtr->calibImage, cornerFinderDataPtr->videoFrame, vs->getVideoWidth()); // Last parameter is rowBytes.
                
                // Spawn the corner finder worker thread.
                cornerFinderThread = threadInit(0, (void*)(cornerFinderDataPtr), cornerFinder);
                
                // Corner finder results copy, for display to user.
                arMalloc(gCorners, CvPoint2D32f, gChessboardCornerNumX*gChessboardCornerNumY);
                arMalloc(gCornerFinderImage, ARUint8, vs->getVideoWidth()*vs->getVideoHeight());
                pthread_mutex_init(&gCornerFinderResultLock, NULL);
                
                if (!flowInitAndStart(gCalibImageNum)) {
                    ARLOGe("Error: Could not initialise and start flow.\n");
                    quit(-1);
                }
                
                // For FPS statistics.
                arUtilTimerReset();
                gCallCountMarkerDetect = 0;
                
                postVideoSetupDone = true;
            } // !postVideoSetupDone
            
            if (vs->captureFrame()) {
                gCallCountMarkerDetect++; // Increment ARToolKit FPS counter.
#ifdef DEBUG
                if (gCallCountMarkerDetect % 150 == 0) {
                    ARLOGi("*** Camera - %f (frame/sec)\n", (double)gCallCountMarkerDetect/arUtilTimer());
                    gCallCountMarkerDetect = 0;
                    arUtilTimerReset();
                }
#endif
                
                FLOW_STATE state = flowStateGet();
                if (state == FLOW_STATE_WELCOME || state == FLOW_STATE_DONE || state == FLOW_STATE_CALIBRATING) {
                    
                    // Upload the frame to OpenGL.
                    // Now done as part of the draw call.
                    
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
                        for (int i = 0; i < cornerFinderData->chessboardCornerNumX*cornerFinderData->chessboardCornerNumY; i++) gCorners[i] = cornerFinderData->corners[i];
                        memcpy(gCornerFinderImage, cornerFinderData->videoFrame, vs->getVideoWidth()*vs->getVideoHeight()); // For the visual overlay of corner locations to be accurate, we need a copy of the image in which they were found.
                        arglPixelBufferDataUpload(gArglSettingsCornerFinderImage, gCornerFinderImage);
                        pthread_mutex_unlock(&gCornerFinderResultLock);
                    }
                    
                    // If corner finder worker thread is ready and waiting, submit the new image.
                    if (!threadGetBusyStatus(cornerFinderThread)) {
                        // As corner finding takes longer than a single frame capture, we need to copy the incoming image
                        // so that OpenCV has exclusive use of it. We copy into cornerFinderData->videoFrame which provides
                        // the backing for calibImage.
                        AR2VideoBufferT *buff = vs->checkoutFrameIfNewerThan({0,0});
                        if (buff) {
                            CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(cornerFinderThread);
                            memcpy(cornerFinderData->videoFrame, buff->buffLuma, vs->getVideoWidth()*vs->getVideoHeight());
                            vs->checkinFrame();
                            
                            // Kick off a new cycle of the cornerFinder. The results will be collected on a subsequent cycle.
                            ARLOGd("processFrame: corner find GO\n");
                            threadStartSignal(cornerFinderThread);
                        }
                    }
                    
                    //
                    // End of main calibration-related cycle.
                    //
                }
                
                // The display has changed.
                drawView();
                
            }
            
        } // vs->isOpen()
        
        
        arUtilSleep(1); // 1 millisecond.
    }
    
    quit(0);
}

void reshape(int w, int h)
{
    contextWidth = w;
    contextHeight = h;
    ARLOGd("Resized to %dx%d.\n", w, h);
    contextWasUpdated = true;
}

bool cornerFinderResultsLockAndFetchCornerFlag(int *cornerFlag, int *cornerCount, CvPoint2D32f **corners)
{
    pthread_mutex_lock(&gCornerFinderResultLock);
    *cornerFlag = gCornerFlag;
    *cornerCount = gCornerCount;
    *corners = gCorners;
    return true;
}

bool cornerFinderResultsUnlock(void)
{
    pthread_mutex_unlock(&gCornerFinderResultLock);
    return true;
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

void stop(void)
{
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
    
    if (gArglSettingsCornerFinderImage) {
        arglCleanup(gArglSettingsCornerFinderImage); // Clean up any left-over ARGL data.
        gArglSettingsCornerFinderImage = NULL;
    }
    
    delete vv;
    vv = nullptr;
    
    delete vs;
    vs = nullptr;
}

static void quit(int rc)
{
    
    // Calibration input cleanup.
    free(gCornerSet);
    gCornerSet = NULL;
    
    fileUploaderFinal(&fileUploadHandle);
    
    SDL_Quit();
    exit(rc);
}

static void usage(char *com)
{
    ARLOG("Usage: %s [options]\n", com);
    ARLOG("Options:\n");
    ARLOG("  --vconf <video parameter for the camera>\n");
    ARLOG("  -cornerx=n: specify the number of corners on chessboard in X direction.\n");
    ARLOG("  -cornery=n: specify the number of corners on chessboard in Y direction.\n");
    ARLOG("  -imagenum=n: specify the number of images captured for calibration.\n");
    ARLOG("  -pattwidth=n: specify the square width in the chessbaord.\n");
    ARLOG("  -h -help --help: show this message\n");
    exit(0);
}

/*
static void init(int argc, char *argv[])
{
    ARGViewport     viewport;
    char           *vconf = NULL;
    int             i;
    int             gotTwoPartOption;
    int             screenWidth, screenHeight, screenMargin;
    
    chessboardCornerNumX = 0;
    chessboardCornerNumY = 0;
    calibImageNum        = 0;
    patternWidth         = 0.0f;
    
    arMalloc(cwd, char, MAXPATHLEN);
    if (!getcwd(cwd, MAXPATHLEN)) ARLOGe("Unable to read current working directory.\n");
    else ARLOG("Current working directory is '%s'\n", cwd);
    
    i = 1; // argv[0] is name of app, so start at 1.
    while (i < argc) {
        gotTwoPartOption = FALSE;
        // Look for two-part options first.
        if ((i + 1) < argc) {
            if (strcmp(argv[i], "--vconf") == 0) {
                i++;
                vconf = argv[i];
                gotTwoPartOption = TRUE;
            }
        }
        if (!gotTwoPartOption) {
            // Look for single-part options.
            if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-help") == 0 || strcmp(argv[i], "-h") == 0) {
                usage(argv[0]);
            } else if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-version") == 0 || strcmp(argv[i], "-v") == 0) {
                ARLOG("%s version %s\n", argv[0], AR_HEADER_VERSION_STRING);
                exit(0);
            } else if( strncmp(argv[i], "-cornerx=", 9) == 0 ) {
                if( sscanf(&(argv[i][9]), "%d", &chessboardCornerNumX) != 1 ) usage(argv[0]);
                if( chessboardCornerNumX <= 0 ) usage(argv[0]);
            } else if( strncmp(argv[i], "-cornery=", 9) == 0 ) {
                if( sscanf(&(argv[i][9]), "%d", &chessboardCornerNumY) != 1 ) usage(argv[0]);
                if( chessboardCornerNumY <= 0 ) usage(argv[0]);
            } else if( strncmp(argv[i], "-imagenum=", 10) == 0 ) {
                if( sscanf(&(argv[i][10]), "%d", &calibImageNum) != 1 ) usage(argv[0]);
                if( calibImageNum <= 0 ) usage(argv[0]);
            } else if( strncmp(argv[i], "-pattwidth=", 11) == 0 ) {
                if( sscanf(&(argv[i][11]), "%f", &patternWidth) != 1 ) usage(argv[0]);
                if( patternWidth <= 0 ) usage(argv[0]);
            } else {
                ARLOGe("Error: invalid command line argument '%s'.\n", argv[i]);
                usage(argv[0]);
            }
        }
        i++;
    }
    if( chessboardCornerNumX == 0 ) chessboardCornerNumX = CHESSBOARD_CORNER_NUM_X;
    if( chessboardCornerNumY == 0 ) chessboardCornerNumY = CHESSBOARD_CORNER_NUM_Y;
    if( calibImageNum == 0 )        calibImageNum = CALIB_IMAGE_NUM;
    if( patternWidth == 0.0f )       patternWidth = (float)CHESSBOARD_PATTERN_WIDTH;
    ARLOG("CHESSBOARD_CORNER_NUM_X = %d\n", chessboardCornerNumX);
    ARLOG("CHESSBOARD_CORNER_NUM_Y = %d\n", chessboardCornerNumY);
    ARLOG("CHESSBOARD_PATTERN_WIDTH = %f\n", patternWidth);
    ARLOG("CALIB_IMAGE_NUM = %d\n", calibImageNum);
    ARLOG("Video parameter: %s\n", vconf);
    
    if (!(gVid = ar2VideoOpen(vconf))) exit(0);
    if (ar2VideoGetSize(gVid, &xsize, &ysize) < 0) exit(0);
    ARLOG("Image size (x,y) = (%d,%d)\n", xsize, ysize);
    if ((pixFormat = ar2VideoGetPixelFormat(gVid)) == AR_PIXEL_FORMAT_INVALID) exit(0);
    
    screenWidth = glutGet(GLUT_SCREEN_WIDTH);
    screenHeight = glutGet(GLUT_SCREEN_HEIGHT);
    if (screenWidth > 0 && screenHeight > 0) {
        screenMargin = (int)(MAX(screenWidth, screenHeight) * SCREEN_SIZE_MARGIN);
        if ((screenWidth - screenMargin) < xsize || (screenHeight - screenMargin) < ysize) {
            viewport.xsize = screenWidth - screenMargin;
            viewport.ysize = screenHeight - screenMargin;
            ARLOG("Scaling window to fit onto %dx%d screen (with %2.0f%% margin).\n", screenWidth, screenHeight, SCREEN_SIZE_MARGIN*100.0);
        } else {
            viewport.xsize = xsize;
            viewport.ysize = ysize;
        }
    } else {
        viewport.xsize = xsize;
        viewport.ysize = ysize;
    }
    viewport.sx = 0;
    viewport.sy = 0;
    if( (vp=argCreateViewport(&viewport)) == NULL ) exit(0);
    argViewportSetImageSize( vp, xsize, ysize );
    argViewportSetPixFormat( vp, pixFormat );
    argViewportSetDispMethod( vp, AR_GL_DISP_METHOD_TEXTURE_MAPPING_FRAME );
    argViewportSetDistortionMode( vp, AR_GL_DISTORTION_COMPENSATE_DISABLE );
    argViewportSetDispMode(vp, AR_GL_DISP_MODE_FIT_TO_VIEWPORT_KEEP_ASPECT_RATIO);
    
    // Set up the grayscale image. We must always copy, since we need OpenCV to be able to wrap the memory.
    arMalloc(imageLumaCopy, ARUint8, xsize*ysize);
    calibImage = cvCreateImageHeader( cvSize(xsize, ysize), IPL_DEPTH_8U, 1);
    cvSetData(calibImage, imageLumaCopy, xsize); // Last parameter is rowBytes.
    
    // Allocate space for results.
    arMalloc(corners, CvPoint2D32f, chessboardCornerNumX*chessboardCornerNumY);
    arMalloc(cornerSet, CvPoint2D32f, chessboardCornerNumX*chessboardCornerNumY*calibImageNum);
}
*/

static void drawBackground(const float width, const float height, const float x, const float y, const bool drawBorder)
{
    GLfloat vertices[4][2];
    
    vertices[0][0] = x; vertices[0][1] = y;
    vertices[1][0] = width + x; vertices[1][1] = y;
    vertices[2][0] = width + x; vertices[2][1] = height + y;
    vertices[3][0] = x; vertices[3][1] = height + y;
    
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glDisable(GL_TEXTURE_2D);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glEnableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glClientActiveTexture(GL_TEXTURE0);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glColor4f(0.0f, 0.0f, 0.0f, 0.5f);	// 50% transparent black.
    glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
    if (drawBorder) {
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f); // Opaque white.
        glLineWidth(1.0f);
        glDrawArrays(GL_LINE_LOOP, 0, 4);
    }
}

// An animation while we're waiting.
// Designed to be drawn on background of at least 3xsquareSize wide and tall.
static void drawBusyIndicator(int positionX, int positionY, int squareSize, struct timeval *tp)
{
    const GLfloat square_vertices [4][2] = { {0.5f, 0.5f}, {squareSize - 0.5f, 0.5f}, {squareSize - 0.5f, squareSize - 0.5f}, {0.5f, squareSize - 0.5f} };
    int i;
    
    int hundredthSeconds = (int)tp->tv_usec / 1E4;
    
    // Set up drawing.
    glPushMatrix();
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_BLEND);
    glVertexPointer(2, GL_FLOAT, 0, square_vertices);
    glEnableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
    glClientActiveTexture(GL_TEXTURE0);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    
    for (i = 0; i < 4; i++) {
        glLoadIdentity();
        glTranslatef((float)(positionX + ((i + 1)/2 != 1 ? -squareSize : 0.0f)), (float)(positionY + (i / 2 == 0 ? 0.0f : -squareSize)), 0.0f); // Order: UL, UR, LR, LL.
        if (i == hundredthSeconds / 25) {
            char r, g, b;
            int secDiv255 = (int)tp->tv_usec / 3921;
            int secMod6 = tp->tv_sec % 6;
            if (secMod6 == 0) {
                r = 255; g = secDiv255; b = 0;
            } else if (secMod6 == 1) {
                r = secDiv255; g = 255; b = 0;
            } else if (secMod6 == 2) {
                r = 0; g = 255; b = secDiv255;
            } else if (secMod6 == 3) {
                r = 0; g = secDiv255; b = 255;
            } else if (secMod6 == 4) {
                r = secDiv255; g = 0; b = 255;
            } else {
                r = 255; g = 0; b = secDiv255;
            }
            glColor4ub(r, g, b, 255);
            glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
        }
        glColor4ub(255, 255, 255, 255);
        glDrawArrays(GL_LINE_LOOP, 0, 4);
    }
    
    glPopMatrix();
}

void drawView(void)
{
    int i;
    struct timeval time;
    float left, right, bottom, top;
    GLfloat *vertices;
    GLint vertexCount;
    
    // Get frame time.
    gettimeofday(&time, NULL);
    
    SDL_GL_MakeCurrent(gSDLWindow, gSDLContext);
    
    // Clean the OpenGL context.
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    //
    // Setup for drawing video frame.
    //
    glViewport(gViewport[0], gViewport[1], gViewport[2], gViewport[3]);
    
    FLOW_STATE state = flowStateGet();
    if (state == FLOW_STATE_WELCOME || state == FLOW_STATE_DONE || state == FLOW_STATE_CALIBRATING) {
        
        // Display the current frame
        vv->draw(vs);
        
    } else if (state == FLOW_STATE_CAPTURING) {
        
        // Grab a lock while we're using the data to prevent it being changed underneath us.
        int cornerFlag;
        int cornerCount;
        CvPoint2D32f *corners;
        cornerFinderResultsLockAndFetchCornerFlag(&cornerFlag, &cornerCount, &corners);
        
        // Display the current frame
        arglDispImage(gArglSettingsCornerFinderImage, NULL);
        
        //
        // Setup for drawing on top of video frame, in video pixel coordinates.
        //
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        if (vv->rotate90()) glRotatef(90.0f, 0.0f, 0.0f, -1.0f);
        if (vv->flipV()) {
            bottom = (float)vs->getVideoHeight();
            top = 0.0f;
        } else {
            bottom = 0.0f;
            top = (float)vs->getVideoHeight();
        }
        if (vv->flipH()) {
            left = (float)vs->getVideoWidth();
            right = 0.0f;
        } else {
            left = 0.0f;
            right = (float)vs->getVideoWidth();
        }
        glOrtho(left, right, bottom, top, -1.0f, 1.0f);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_LIGHTING);
        glDisable(GL_BLEND);
        glActiveTexture(GL_TEXTURE0);
        glDisable(GL_TEXTURE_2D);
        
        if (cornerFlag) glColor4ub(255, 0, 0, 255);
        else glColor4ub(0, 255, 0, 255);
        
        
        // Draw the crosses marking the corner positions.
        float fontSizeScaled = FONT_SIZE * (float)vs->getVideoHeight()/(float)(gViewport[(gDisplayOrientation % 2) == 1 ? 3 : 2]);
        EdenGLFontSetSize(fontSizeScaled);
        vertexCount = cornerCount*4;
        if (vertexCount > 0) {
            arMalloc(vertices, GLfloat, vertexCount*2); // 2 coords per vertex.
            for (i = 0; i < cornerCount; i++) {
                vertices[i*8    ] = corners[i].x - 5.0f;
                vertices[i*8 + 1] = vs->getVideoHeight() - corners[i].y - 5.0f;
                vertices[i*8 + 2] = corners[i].x + 5.0f;
                vertices[i*8 + 3] = vs->getVideoHeight() - corners[i].y + 5.0f;
                vertices[i*8 + 4] = corners[i].x - 5.0f;
                vertices[i*8 + 5] = vs->getVideoHeight() - corners[i].y + 5.0f;
                vertices[i*8 + 6] = corners[i].x + 5.0f;
                vertices[i*8 + 7] = vs->getVideoHeight() - corners[i].y - 5.0f;
                
                unsigned char buf[12]; // 10 digits in INT32_MAX, plus sign, plus null.
                sprintf((char *)buf, "%d\n", i);
                
                glPushMatrix();
                glLoadIdentity();
                glTranslatef(corners[i].x, vs->getVideoHeight() - corners[i].y, 0.0f);
                glRotatef((float)(gDisplayOrientation - 1) * -90.0f, 0.0f, 0.0f, 1.0f); // Orient the text to the user.
                EdenGLFontDrawLine(0, buf, 0.0f, 0.0f, H_OFFSET_VIEW_LEFT_EDGE_TO_TEXT_LEFT_EDGE, V_OFFSET_VIEW_BOTTOM_TO_TEXT_BASELINE); // These alignment modes don't require setting of EdenGLFontSetViewSize().
                glPopMatrix();
            }
        }
        EdenGLFontSetSize(FONT_SIZE);
        
        cornerFinderResultsUnlock();
        
        if (vertexCount > 0) {
            glVertexPointer(2, GL_FLOAT, 0, vertices);
            glEnableClientState(GL_VERTEX_ARRAY);
            glDisableClientState(GL_NORMAL_ARRAY);
            glClientActiveTexture(GL_TEXTURE0);
            glDisableClientState(GL_TEXTURE_COORD_ARRAY);
            glLineWidth(2.0f);
            glDrawArrays(GL_LINES, 0, vertexCount);
            free(vertices);
        }
    }
    
    //
    // Setup for drawing on top of video frame, in viewPort coordinates.
    //
#if 0
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    bottom = 0.0f;
    top = (float)(viewPort[viewPortIndexHeight]);
    left = 0.0f;
    right = (float)(viewPort[viewPortIndexWidth]);
    glOrthof(left, right, bottom, top, -1.0f, 1.0f);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    
    EdenGLFontSetViewSize(right, top);
    EdenMessageSetViewSize(right, top, gDisplayDPI);
#endif
    
    //
    // Setup for drawing on screen, with correct orientation for user.
    //
    glViewport(0, 0, contextWidth, contextHeight);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    bottom = 0.0f;
    top = (float)contextHeight;
    left = 0.0f;
    right = (float)contextWidth;
    glOrtho(left, right, bottom, top, -1.0f, 1.0f);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    
    EdenGLFontSetViewSize(right, top);
    EdenMessageSetViewSize(right, top);
    EdenMessageSetBoxParams(350.0f, 20.0f);
    
    // Draw status bar with centred status message.
    float statusBarHeight = EdenGLFontGetHeight() + 4.0f; // 2 pixels above, 2 below.
    drawBackground(right, statusBarHeight, 0.0f, 0.0f, false);
    glDisable(GL_BLEND);
    glColor4ub(255, 255, 255, 255);
    EdenGLFontDrawLine(0, statusBarMessage, 0.0f, 2.0f, H_OFFSET_VIEW_CENTER_TO_TEXT_CENTER, V_OFFSET_VIEW_BOTTOM_TO_TEXT_BASELINE);
    
    
    // If background tasks are proceeding, draw a status box.
    char uploadStatus[UPLOAD_STATUS_BUFFER_LEN];
    int status = fileUploaderStatusGet(fileUploadHandle, uploadStatus, &time);
    if (status) {
        const int squareSize = (int)(16.0f * (float)gDisplayDPI / 160.f) ;
        float x, y, w, h;
        float textWidth = EdenGLFontGetLineWidth((unsigned char *)uploadStatus);
        w = textWidth + 3*squareSize + 2*4.0f /*text margin*/ + 2*4.0f /* box margin */;
        h = MAX(FONT_SIZE, 3*squareSize) + 2*4.0f /* box margin */;
        x = right - (w + 2.0f);
        y = statusBarHeight + 2.0f;
        drawBackground(w, h, x, y, true);
        if (status == 1) drawBusyIndicator((int)(x + 4.0f + 1.5f*squareSize), (int)(y + 4.0f + 1.5f*squareSize), squareSize, &time);
        EdenGLFontDrawLine(0, (unsigned char *)uploadStatus, x + 4.0f + 3*squareSize, y + (h - FONT_SIZE)/2.0f, H_OFFSET_VIEW_LEFT_EDGE_TO_TEXT_LEFT_EDGE, V_OFFSET_VIEW_BOTTOM_TO_TEXT_BASELINE);
    }
    
    // If a message should be onscreen, draw it.
    if (gEdenMessageDrawRequired) EdenMessageDraw(0);
    
    SDL_GL_SwapWindow(gSDLWindow);
}

extern "C" bool capture(const int capturedImageNum)
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

extern "C" void calib(ARParam *param_out, ARdouble *err_min_out, ARdouble *err_avg_out, ARdouble *err_max_out)
{
    calc(gCalibImageNum, gChessboardCornerNumX, gChessboardCornerNumY, gChessboardSquareWidth, gCornerSet, vs->getVideoWidth(), vs->getVideoHeight(), param_out, err_min_out, err_avg_out, err_max_out);
}

// Save parameters file and index file with info about it, then signal thread that it's ready for upload.
extern "C" void saveParam(const ARParam *param, ARdouble err_min, ARdouble err_avg, ARdouble err_max)
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
            char *os_name = arUtilGetOSName();
            char *os_arch = arUtilGetCPUName();
            char *os_version = arUtilGetOSVersion();
            fprintf(fp, "os_name,%s\nos_arch,%s\nos_version,%s\n", os_name, os_arch, os_version);
            free(os_name);
            free(os_arch);
            free(os_version);
        }
        
        // Camera identifier.
        if (goodWrite) {
            char *device_id = NULL;
            AR2VideoParamT *vid = vs->getAR2VideoParam();
            if (ar2VideoGetParams(vid, AR_VIDEO_PARAM_DEVICEID, &device_id) < 0 || !device_id) {
                ARLOGe("Error fetching camera device identification.\n");
                goodWrite = false;
            } else {
                fprintf(fp, "device_id,%s\n", device_id);
                free(device_id);
            }
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
            snprintf(camera_width, 12, "%d", vs->getVideoWidth());
            snprintf(camera_height, 12, "%d", vs->getVideoHeight());
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
            char ss[] = SHARED_SECRET;
            unsigned char ss_md5[MD5_DIGEST_LENGTH];
            char ss_ascii[MD5_DIGEST_LENGTH*2 + 1]; // space for null terminator.
            if (!MD5((unsigned char *)ss, strlen(ss), ss_md5)) {
                ARLOGe("Error calculating md5.\n");
                goodWrite = false;
            } else {
                for (i = 0; i < MD5_DIGEST_LENGTH; i++) snprintf(&(ss_ascii[i*2]), 3, "%.2hhx", ss_md5[i]);
                fprintf(fp, "ss,%s\n", ss_ascii);
            }
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



