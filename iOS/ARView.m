//
//  ARView.m
//  ARToolKit for iOS
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
//  Author(s): Philip Lamb
//

#import <QuartzCore/QuartzCore.h>
#import "ARView.h"
#import "ARViewController.h"
#import "glStateCache.h"
#import <AR/gsub_es.h>
#import <AR/gsub_mtx.h>
#import <Eden/EdenMath.h>
#import <Eden/EdenGLFont.h>
#import <Eden/EdenMessage.h>
#import <sys/time.h> // struct timeval, gettimeofday()
#import "flow.h"
#import "fileUploader.h"

NSString *const ARViewUpdatedCameraLensNotification = @"ARViewUpdatedCameraLensNotification";
NSString *const ARViewUpdatedCameraPoseNotification = @"ARViewUpdatedCameraPoseNotification";
NSString *const ARViewUpdatedViewportNotification = @"ARViewUpdatedViewportNotification";
NSString *const ARViewDrawPreCameraNotification = @"ARViewDrawPreCameraNotification";
NSString *const ARViewDrawPostCameraNotification = @"ARViewDrawPostCameraNotification";
NSString *const ARViewDrawOverlayNotification = @"ARViewDrawOverlayNotification";
NSString *const ARViewTouchNotification = @"ARViewTouchNotification";

@interface ARView (ARViewPrivate)
- (void) calculateProjection;
@end

@implementation ARView {
    
    ARViewController *arViewController;
    
    float cameraLens[16];
    float cameraPose[16];
    BOOL cameraPoseValid;
    int contentWidth;
    int contentHeight;
    BOOL contentRotate90;
    BOOL contentFlipH;
    BOOL contentFlipV;
    ARViewContentScaleMode contentScaleMode;
    ARViewContentAlignMode contentAlignMode;

    float projection[16];
    GLint viewPort[4];
    
    // Interaction.
    id <ARViewTouchDelegate> touchDelegate;
    
    BOOL rayIsValid;
    ARVec3 rayPoint1;
    ARVec3 rayPoint2;

    float gDisplayDPI;
}

@synthesize contentWidth, contentHeight, contentAlignMode, contentScaleMode, touchDelegate, arViewController;
@synthesize rayIsValid, rayPoint1, rayPoint2;

- (id) initWithFrame:(CGRect)frame pixelFormat:(NSString*)format depthFormat:(EAGLDepthFormat)depth withStencil:(BOOL)stencil preserveBackbuffer:(BOOL)retained
{
    if ((self = [super initWithFrame:frame renderingAPI:kEAGLRenderingAPIOpenGLES1 pixelFormat:format depthFormat:depth withStencil:stencil preserveBackbuffer:retained maxScale:2.0f])) {
         
        // Init instance variables.
        arViewController = nil;
        
        mtxLoadIdentityf(cameraLens);
        contentRotate90 = contentFlipH = contentFlipV = NO;
        mtxLoadIdentityf(projection);
        
        contentWidth = (int)frame.size.width;
        contentHeight = (int)frame.size.height;
        contentScaleMode = ARViewContentScaleModeFill;
        contentAlignMode = ARViewContentAlignModeCenter;

        cameraPoseValid = NO;
        
        // Init gestures.
        [self setMultipleTouchEnabled:YES];
        [self setTouchDelegate:self];

        // One-time OpenGL setup goes here.
        glStateCacheFlush();
        
        gDisplayDPI = 160.0f; // iOS default.
        // Also do DPI now.
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            gDisplayDPI = 132.0f * self.contentScaleFactor;
        } else if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            gDisplayDPI = 163.0f * self.contentScaleFactor;
        } else {
            gDisplayDPI = 160.0f * self.contentScaleFactor;
        }

        int contextsActiveCount = 1;
        EdenGLFontInit(contextsActiveCount);
        EdenGLFontSetSize(FONT_SIZE);
        EdenGLFontSetFont(EDEN_GL_FONT_ID_Stroke_Roman);
        EdenGLFontSetWordSpacing(0.8f);
        EdenGLFontSetDisplayResolution((float)gDisplayDPI);
        
        BOOL __unused ok = CHECK_GL_ERROR();
        
    }
    
    return (self);
    
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    // Calculate viewport.
    int left, bottom, w, h;
    
#ifdef DEBUG
    NSLog(@"[ARView layoutSubviews] backingWidth=%d, backingHeight=%d\n", self.backingWidth, self.backingHeight);
#endif        

    if (self.contentScaleMode == ARViewContentScaleModeStretch) {
        w = self.backingWidth;
        h = self.backingHeight;
    } else {
        int contentWidthFinalOrientation = (contentRotate90 ? contentHeight : contentWidth);
        int contentHeightFinalOrientation = (contentRotate90 ? contentWidth : contentHeight);
        if (self.contentScaleMode == ARViewContentScaleModeFit || self.contentScaleMode == ARViewContentScaleModeFill) {
            float scaleRatioWidth, scaleRatioHeight, scaleRatio;
            scaleRatioWidth = (float)self.backingWidth / (float)contentWidthFinalOrientation;
            scaleRatioHeight = (float)self.backingHeight / (float)contentHeightFinalOrientation;
            if (self.contentScaleMode == ARViewContentScaleModeFill) scaleRatio = MAX(scaleRatioHeight, scaleRatioWidth);
            else scaleRatio = MIN(scaleRatioHeight, scaleRatioWidth);
            w = (int)((float)contentWidthFinalOrientation * scaleRatio);
            h = (int)((float)contentHeightFinalOrientation * scaleRatio);
        } else {
            w = contentWidthFinalOrientation;
            h = contentHeightFinalOrientation;
        }
    }
    
    if (self.contentAlignMode == ARViewContentAlignModeTopLeft
        || self.contentAlignMode == ARViewContentAlignModeLeft
        || self.contentAlignMode == ARViewContentAlignModeBottomLeft) left = 0;
    else if (self.contentAlignMode == ARViewContentAlignModeTopRight
             || self.contentAlignMode == ARViewContentAlignModeRight
             || self.contentAlignMode == ARViewContentAlignModeBottomRight) left = self.backingWidth - w;
    else left = (self.backingWidth - w) / 2;
        
    if (self.contentAlignMode == ARViewContentAlignModeBottomLeft
        || self.contentAlignMode == ARViewContentAlignModeBottom
        || self.contentAlignMode == ARViewContentAlignModeBottomRight) bottom = 0;
    else if (self.contentAlignMode == ARViewContentAlignModeTopLeft
             || self.contentAlignMode == ARViewContentAlignModeTop
             || self.contentAlignMode == ARViewContentAlignModeTopRight) bottom = self.backingHeight - h;
    else bottom = (self.backingHeight - h) / 2;

    glViewport(left, bottom, w, h);
    
    viewPort[viewPortIndexLeft] = left;
    viewPort[viewPortIndexBottom] = bottom;
    viewPort[viewPortIndexWidth] = w;
    viewPort[viewPortIndexHeight] = h;
    [[NSNotificationCenter defaultCenter] postNotificationName:ARViewUpdatedViewportNotification object:self];
#ifdef DEBUG
    NSLog(@"[ARView layoutSubviews] viewport left=%d, bottom=%d, width=%d, height=%d\n", left, bottom, w, h);
#endif
}

- (GLint *)viewPort
{
    return (viewPort);
}

- (void)setCameraLens:(float *)lens
{
    if (lens) {
        mtxLoadMatrixf(cameraLens, lens);
        [self calculateProjection];
    }
}

- (float *)cameraLens
{
    return (projection);
}

- (void) setContentRotate90:(BOOL)contentRotate90_in
{
    contentRotate90 = contentRotate90_in;
    [self calculateProjection];
}

- (BOOL) contentRotate90
{
    return (contentRotate90);
}

- (void) setContentFlipH:(BOOL)contentFlipH_in
{
    contentFlipH = contentFlipH_in;
    [self calculateProjection];
}

- (BOOL) contentFlipH
{
    return (contentFlipH);
}

- (void) setContentFlipV:(BOOL)contentFlipV_in
{
    contentFlipV = contentFlipV_in;
    [self calculateProjection];
}

- (BOOL) contentFlipV
{
    return (contentFlipV);
}

- (void) calculateProjection
{
    float const ir90[16] = {0.0f, -1.0f, 0.0f, 0.0f,  1.0f, 0.0f, 0.0f, 0.0f,  0.0f, 0.0f, 1.0f, 0.0f,  0.0f, 0.0f, 0.0f, 1.0f};
    
    if (contentRotate90) mtxLoadMatrixf(projection, ir90);
    else mtxLoadIdentityf(projection);
    if (contentFlipH || contentFlipV) mtxScalef(projection, (contentFlipH ? -1.0f : 1.0f), (contentFlipV ? -1.0f : 1.0f), 1.0f);
    mtxMultMatrixf(projection, cameraLens);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ARViewUpdatedCameraLensNotification object:self];
}

- (void)setCameraPose:(float *)pose
{
    if (pose) {
        int i;
        for (i = 0; i < 16; i++) cameraPose[i] = pose[i];
        cameraPoseValid = TRUE;
        [[NSNotificationCenter defaultCenter] postNotificationName:ARViewUpdatedCameraPoseNotification object:self];
    } else {
        cameraPoseValid = FALSE;
    }
}

- (float *)cameraPose
{
    if (cameraPoseValid) return (cameraPose);
    else return (NULL);
}

static void drawBackground(const float width, const float height, const float x, const float y, const bool drawBorder)
{
    GLfloat vertices[4][2];
    
    vertices[0][0] = x; vertices[0][1] = y;
    vertices[1][0] = width + x; vertices[1][1] = y;
    vertices[2][0] = width + x; vertices[2][1] = height + y;
    vertices[3][0] = x; vertices[3][1] = height + y;
    
    glLoadIdentity();
    glStateCacheDisableDepthTest();
    glStateCacheDisableLighting();
    glStateCacheDisableTex2D();
    glStateCacheBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glStateCacheEnableBlend();
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glStateCacheEnableClientStateVertexArray();
    glStateCacheDisableClientStateNormalArray();
    glStateCacheClientActiveTexture(GL_TEXTURE0);
    glStateCacheDisableClientStateTexCoordArray();
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
    glStateCacheDisableDepthTest();
    glStateCacheDisableLighting();
    glStateCacheDisableTex2D();
    glStateCacheDisableBlend();
    glVertexPointer(2, GL_FLOAT, 0, square_vertices);
    glStateCacheEnableClientStateVertexArray();
    glStateCacheDisableClientStateNormalArray();
    glStateCacheClientActiveTexture(GL_TEXTURE0);
    glStateCacheDisableClientStateTexCoordArray();
    glStateCacheEnableClientStateVertexArray();
    
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

- (void) drawView:(id)sender
{
    int i;
    struct timeval time;
    float left, right, bottom, top;
    GLfloat *vertices;
    GLint vertexCount;
    
    // Get frame time.
    gettimeofday(&time, NULL);
    
    [self clearBuffers];
    
    //
    // Setup for drawing video frame.
    //
    glViewport(viewPort[viewPortIndexLeft], viewPort[viewPortIndexBottom], viewPort[viewPortIndexWidth], viewPort[viewPortIndexHeight]);
    
    FLOW_STATE state = flowStateGet();
    if (state == FLOW_STATE_WELCOME || state == FLOW_STATE_DONE || state == FLOW_STATE_CALIBRATING) {
        
        // Display the current frame
        arglDispImage(arViewController.gArglSettings);
        
    } else if (state == FLOW_STATE_CAPTURING) {
        
        // Grab a lock while we're using the data to prevent it being changed underneath us.
        int cornerFlag;
        int cornerCount;
        CvPoint2D32f *corners;
        [arViewController cornerFinderResultsLockAndFetchCornerFlag:&cornerFlag cornerCount:&cornerCount corners:&corners];
        
        // Display the current frame
        arglDispImage(arViewController.gArglSettingsCornerFinderImage);
        
        //
        // Setup for drawing on top of video frame, in video pixel coordinates.
        //
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        if (contentRotate90) glRotatef(90.0f, 0.0f, 0.0f, -1.0f);
        if (contentFlipV) {
            bottom = (float)contentHeight;
            top = 0.0f;
        } else {
            bottom = 0.0f;
            top = (float)contentHeight;
        }
        if (contentFlipH) {
            left = (float)contentWidth;
            right = 0.0f;
        } else {
            left = 0.0f;
            right = (float)contentWidth;
        }
        glOrthof(left, right, bottom, top, -1.0f, 1.0f);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glStateCacheDisableDepthTest();
        glStateCacheDisableLighting();
        glStateCacheDisableBlend();
        glStateCacheActiveTexture(GL_TEXTURE0);
        glStateCacheDisableTex2D();
        
        if (cornerFlag) glColor4ub(255, 0, 0, 255);
        else glColor4ub(0, 255, 0, 255);
        
        
        // Draw the crosses marking the corner positions.
        float fontSizeScaled = FONT_SIZE * (float)contentHeight/(float)(viewPort[(arViewController.gDisplayOrientation % 2) == 1 ? viewPortIndexHeight : viewPortIndexWidth]);
        EdenGLFontSetSize(fontSizeScaled);
        vertexCount = cornerCount*4;
        if (vertexCount > 0) {
            arMalloc(vertices, GLfloat, vertexCount*2); // 2 coords per vertex.
            for (i = 0; i < cornerCount; i++) {
                vertices[i*8    ] = corners[i].x - 5.0f;
                vertices[i*8 + 1] = contentHeight - corners[i].y - 5.0f;
                vertices[i*8 + 2] = corners[i].x + 5.0f;
                vertices[i*8 + 3] = contentHeight - corners[i].y + 5.0f;
                vertices[i*8 + 4] = corners[i].x - 5.0f;
                vertices[i*8 + 5] = contentHeight - corners[i].y + 5.0f;
                vertices[i*8 + 6] = corners[i].x + 5.0f;
                vertices[i*8 + 7] = contentHeight - corners[i].y - 5.0f;
                
                unsigned char buf[12]; // 10 digits in INT32_MAX, plus sign, plus null.
                sprintf((char *)buf, "%d\n", i);
                
                glPushMatrix();
                glLoadIdentity();
                glTranslatef(corners[i].x, contentHeight - corners[i].y, 0.0f);
                glRotatef((float)(arViewController.gDisplayOrientation - 1) * -90.0f, 0.0f, 0.0f, 1.0f); // Orient the text to the user.
                EdenGLFontDrawLine(0, buf, 0.0f, 0.0f, H_OFFSET_VIEW_LEFT_EDGE_TO_TEXT_LEFT_EDGE, V_OFFSET_VIEW_BOTTOM_TO_TEXT_BASELINE); // These alignment modes don't require setting of EdenGLFontSetViewSize().
                glPopMatrix();
            }
        }
        EdenGLFontSetSize(FONT_SIZE);
        
        [arViewController cornerFinderResultsUnlock];
        
        if (vertexCount > 0) {
            glVertexPointer(2, GL_FLOAT, 0, vertices);
            glStateCacheEnableClientStateVertexArray();
            glStateCacheClientActiveTexture(GL_TEXTURE0);
            glStateCacheDisableClientStateTexCoordArray();
            glStateCacheDisableClientStateNormalArray();
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
    glViewport(0, 0, self.backingWidth, self.backingHeight);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    bottom = 0.0f;
    top = (float)self.backingHeight;
    left = 0.0f;
    right = (float)self.backingWidth;
    glOrthof(left, right, bottom, top, -1.0f, 1.0f);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    
    EdenGLFontSetViewSize(right, top);
    EdenMessageSetViewSize(right, top);
    EdenMessageSetBoxParams(350.0f * self.contentScaleFactor, 20.0f * self.contentScaleFactor);
    
    // Draw status bar with centred status message.
    float statusBarHeight = EdenGLFontGetHeight() + 4.0f; // 2 pixels above, 2 below.
    drawBackground(right, statusBarHeight, 0.0f, 0.0f, false);
    glStateCacheDisableBlend();
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
    
    [self swapBuffers];
}

- (void) dealloc
{
    EdenGLFontFinal();

    [super dealloc];
}

// Handles the start of a touch
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSArray*        array = [touches allObjects];
    UITouch*        touch;
    NSUInteger        i;
    CGPoint            location;
    NSUInteger      numTaps;
    
#ifdef DEBUG
    //NSLog(@"[EAGLView touchesBegan].\n");
#endif
    
    for (i = 0; i < [array count]; ++i) {
        touch = [array objectAtIndex:i];
        if (touch.phase == UITouchPhaseBegan) {
            location = [touch locationInView:self];
            numTaps = [touch tapCount];
            if (touchDelegate) {
                if ([touchDelegate respondsToSelector:@selector(handleTouchAtLocation:tapCount:)]) {
                    [touchDelegate handleTouchAtLocation:location tapCount:numTaps];
                }    
            }
        } // phase match.
    } // touches.
}

// Handles the continuation of a touch.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSArray*        array = [touches allObjects];
    UITouch*        touch;
    NSUInteger        i;
    
#ifdef DEBUG
    //NSLog(@"[EAGLView touchesMoved].\n");
#endif
    
    for (i = 0; i < [array count]; ++i) {
        touch = [array objectAtIndex:i];
        if (touch.phase == UITouchPhaseMoved) {
            // Can do something appropriate for a moving touch here.
         } // phase match.
    } // touches.
}

// Handles the end of a touch event.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSArray*        array = [touches allObjects];
    UITouch*        touch;
    NSUInteger        i;
    
#ifdef DEBUG
    //NSLog(@"[EAGLView touchesEnded].\n");
#endif
    
    for (i = 0; i < [array count]; ++i) {
        touch = [array objectAtIndex:i];
        if (touch.phase == UITouchPhaseEnded) {
            // Can do something appropriate for end of touch here.
        } // phase match.
    } // touches.
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSArray*        array = [touches allObjects];
    UITouch*        touch;
    NSUInteger        i;
    
#ifdef DEBUG
    //NSLog(@"[EAGLView touchesCancelled].\n");
#endif
    
    for (i = 0; i < [array count]; ++i) {
        touch = [array objectAtIndex:i];
        if (touch.phase == UITouchPhaseCancelled) {
               // Can do something appropriate for cancellation of a touch (e.g. by a system event) here.
        } // phase match.
    } // touches.
}

- (void)convertPointInViewToRay:(CGPoint)point
{
    
    float m[16], A[16];
    float p[4], q[4];
    
    // Find INVERSE(PROJECTION * MODELVIEW).
    EdenMathMultMatrix(A, projection, cameraPose);
    if (EdenMathInvertMatrix(m, A)) {
        
        // Next, normalise point to viewport range [-1.0, 1.0], and with depth -1.0 (i.e. at near clipping plane).
        p[0] = (point.x - viewPort[viewPortIndexLeft]) * 2.0f / viewPort[viewPortIndexWidth] - 1.0f; // (winx - viewport[0]) * 2 / viewport[2] - 1.0;
        p[1] = (point.y - viewPort[viewPortIndexBottom]) * 2.0f / viewPort[viewPortIndexHeight] - 1.0f; // (winy - viewport[1]) * 2 / viewport[3] - 1.0;
        p[2] = -1.0f; // 2 * winz - 1.0;
        p[3] = 1.0f;
        
        // Calculate the point's world coordinates.
        EdenMathMultMatrixByVector(q, m, p);
        
        if (q[3] != 0.0f) {
            rayPoint1.v[0] = q[0] / q[3];
            rayPoint1.v[1] = q[1] / q[3];
            rayPoint1.v[2] = q[2] / q[3];
            
            // Next, a second point with depth 1.0 (i.e. at far clipping plane).
            p[2] = 1.0f; // 2 * winz - 1.0;
            
            // Calculate the point's world coordinates.
            EdenMathMultMatrixByVector(q, m, p);
            if (q[3] != 0.0f) {
                
                rayPoint2.v[0] = q[0] / q[3];
                rayPoint2.v[1] = q[1] / q[3];
                rayPoint2.v[2] = q[2] / q[3];
                
                rayIsValid = TRUE;
                return;
            }
        }
    }
    rayIsValid = FALSE;
}

- (void) handleTouchAtLocation:(CGPoint)location tapCount:(NSUInteger)tapCount
{
    CGPoint locationFlippedY = CGPointMake(location.x, self.surfaceSize.height - location.y);
    //NSLog(@"Touch at CG location (%.1f,%.1f), surfaceSize.height makes it (%.1f,%.1f) with y flipped.\n", location.x, location.y, locationFlippedY.x, locationFlippedY.y);
    
    [self convertPointInViewToRay:locationFlippedY];
    if (rayIsValid) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ARViewTouchNotification object:self];
    }
}

@end
