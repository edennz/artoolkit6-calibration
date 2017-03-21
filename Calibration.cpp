//
//  calib.c
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 20/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#include "Calibration.hpp"
#include <opencv2/calib3d/calib3d.hpp>
#include <opencv2/imgproc/imgproc_c.h>
#include "calc.h"


bool Calibration::init(const int calibImageCountMax, const int chessboardCornerNumX, const int chessboardCornerNumY, const int chessboardSquareWidth, const int videoWidth, const int videoHeight)
{
    // Calibration inputs.
    m_calibImageCount = 0;
    m_calibImageCountMax = calibImageCountMax;
    m_chessboardCornerNumX = chessboardCornerNumX;
    m_chessboardCornerNumY = chessboardCornerNumY;
    arMalloc(gCorners, CvPoint2D32f, chessboardCornerNumX*chessboardCornerNumY*calibImageCountMax);
    m_chessboardSquareWidth = chessboardSquareWidth;
    m_videoWidth = videoWidth;
    m_videoHeight = videoHeight;
    
    //
    // Corner finder inputs and outputs.
    //
    CORNER_FINDER_DATA_T* cornerFinderDataPtr;
    arMallocClear(cornerFinderDataPtr, CORNER_FINDER_DATA_T, 1);
    cornerFinderDataPtr->chessboardCornerNumX = chessboardCornerNumX;
    cornerFinderDataPtr->chessboardCornerNumY = chessboardCornerNumY;
    arMalloc(cornerFinderDataPtr->corners, CvPoint2D32f, cornerFinderDataPtr->chessboardCornerNumX * cornerFinderDataPtr->chessboardCornerNumY);
    arMalloc(cornerFinderDataPtr->videoFrame, ARUint8, videoWidth*videoHeight);
    cornerFinderDataPtr->calibImage = cvCreateImageHeader(cvSize(videoWidth, videoHeight), IPL_DEPTH_8U, 1);
    cvSetData(cornerFinderDataPtr->calibImage, cornerFinderDataPtr->videoFrame, videoWidth); // Last parameter is rowBytes.
    
    // Spawn the corner finder worker thread.
    gCornerFinderThread = threadInit(0, (void *)(cornerFinderDataPtr), cornerFinder);
    
    // Corner finder results copy, for display to user.
    arMalloc(gCornerFinderOutputCorners, CvPoint2D32f, chessboardCornerNumX*chessboardCornerNumY);
    arMalloc(gCornerFinderOutputImage, ARUint8, videoWidth*videoHeight);
    gCornerFinderOutputCVImage = cvCreateImageHeader(cvSize(videoWidth, videoHeight), IPL_DEPTH_8U, 1);
    cvSetData(gCornerFinderOutputCVImage, gCornerFinderOutputImage, videoWidth); // Last parameter is rowBytes.
    pthread_mutex_init(&gCornerFinderResultLock, NULL);
    
    return true;
}

bool Calibration::frame(ARVideoSource *vs)
{
    //
    // Start of main calibration-related cycle.
    //
    
    // First, see if an image has been completely processed.
    if (threadGetStatus(gCornerFinderThread)) {
        threadEndWait(gCornerFinderThread); // We know from status above that worker has already finished, so this just resets it.
        ARLOGd("processFrame: corner find DONE.\n");
        
        // Copy the results.
        pthread_mutex_lock(&gCornerFinderResultLock); // Results are also read by GL thread, so need to lock before modifying.
        CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(gCornerFinderThread);
        gCornerFinderOutputFoundAllFlag = cornerFinderData->cornerFoundAllFlag;
        gCornerFinderOutputFoundCount = cornerFinderData->cornerCount;
        for (int i = 0; i < cornerFinderData->chessboardCornerNumX*cornerFinderData->chessboardCornerNumY; i++) gCornerFinderOutputCorners[i] = cornerFinderData->corners[i];
        memcpy(gCornerFinderOutputImage, cornerFinderData->videoFrame, vs->getVideoWidth()*vs->getVideoHeight()); // For the visual overlay of corner locations to be accurate, we need a copy of the image in which they were found.
        pthread_mutex_unlock(&gCornerFinderResultLock);
    }
    
    // If corner finder worker thread is ready and waiting, submit the new image.
    if (!threadGetBusyStatus(gCornerFinderThread)) {
        // As corner finding takes longer than a single frame capture, we need to copy the incoming image
        // so that OpenCV has exclusive use of it. We copy into cornerFinderData->videoFrame which provides
        // the backing for calibImage.
        AR2VideoBufferT *buff = vs->checkoutFrameIfNewerThan({0,0});
        if (buff) {
            CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(gCornerFinderThread);
            memcpy(cornerFinderData->videoFrame, buff->buffLuma, vs->getVideoWidth()*vs->getVideoHeight());
            vs->checkinFrame();
            
            // Kick off a new cycle of the cornerFinder. The results will be collected on a subsequent cycle.
            ARLOGd("processFrame: corner find GO\n");
            threadStartSignal(gCornerFinderThread);
        }
    }
    
    //
    // End of main calibration-related cycle.
    //
    return true;
}

bool Calibration::cornerFinderResultsLockAndFetch(int *cornerFoundAllFlag, int *cornerCount, CvPoint2D32f **corners, ARUint8** videoFrame)
{
    pthread_mutex_lock(&gCornerFinderResultLock);
    *cornerFoundAllFlag = gCornerFinderOutputFoundAllFlag;
    *cornerCount = gCornerFinderOutputFoundCount;
    *corners = gCornerFinderOutputCorners;
    *videoFrame = gCornerFinderOutputImage;
    return true;
}

bool Calibration::cornerFinderResultsUnlock(void)
{
    pthread_mutex_unlock(&gCornerFinderResultLock);
    return true;
}

// Worker thread.
void *Calibration::cornerFinder(THREAD_HANDLE_T *threadHandle)
{
#ifdef DEBUG
    ARLOGi("Start cornerFinder thread.\n");
#endif
    
    CORNER_FINDER_DATA_T  *cornerFinderDataPtr = (CORNER_FINDER_DATA_T *)threadGetArg(threadHandle);
    
    while (threadStartWait(threadHandle) == 0) {
        
        cornerFinderDataPtr->cornerFoundAllFlag = cvFindChessboardCorners(cornerFinderDataPtr->calibImage,
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

bool Calibration::capture()
{
    CvPoint2D32f   *p1, *p2;
    int             i;
    
    if (m_calibImageCount >= m_calibImageCountMax) return false;
   
    bool saved = false;
    
    pthread_mutex_lock(&gCornerFinderResultLock);
    if (gCornerFinderOutputFoundAllFlag) {
        // Refine the corner positions.
        cvFindCornerSubPix(gCornerFinderOutputCVImage,
                           gCornerFinderOutputCorners,
                           m_chessboardCornerNumX*m_chessboardCornerNumY,
                           cvSize(5,5),
                           cvSize(-1,-1),
                           cvTermCriteria(CV_TERMCRIT_ITER, 100, 0.1)  );
        
        // Save the corners.
        p1 = gCornerFinderOutputCorners;
        p2 = &gCorners[m_calibImageCount * m_chessboardCornerNumX * m_chessboardCornerNumY];
        for (i = 0; i < m_chessboardCornerNumX * m_chessboardCornerNumY; i++) {
            *(p2++) = *(p1++);
        }
        saved = true;
    }
    pthread_mutex_unlock(&gCornerFinderResultLock);

    if (saved) {
        ARLOG("---------- %2d/%2d -----------\n", m_calibImageCount + 1, m_calibImageCountMax);
        for (i = 0; i < m_chessboardCornerNumX*m_chessboardCornerNumY; i++) {
            ARLOG("  %f, %f\n", gCorners[m_calibImageCount*m_chessboardCornerNumX*m_chessboardCornerNumY + i].x, gCorners[m_calibImageCount*m_chessboardCornerNumX*m_chessboardCornerNumY + i].y);
        }
        ARLOG("---------- %2d/%2d -----------\n", m_calibImageCount + 1, m_calibImageCountMax);
        
        m_calibImageCount++;
    }
    
    return (saved);
}

bool Calibration::uncapture(void)
{
    if (m_calibImageCount < 0) return false;
    m_calibImageCount--;
    return true;
}

void Calibration::calib(ARParam *param_out, ARdouble *err_min_out, ARdouble *err_avg_out, ARdouble *err_max_out)
{
    calc(m_calibImageCount, m_chessboardCornerNumX, m_chessboardCornerNumY, m_chessboardSquareWidth, gCorners, m_videoWidth, m_videoHeight, param_out, err_min_out, err_avg_out, err_max_out);
}

Calibration::~Calibration()
{
    // Clean up results copy.
    // Free space for results.
    if (gCornerFinderOutputCorners) {
        free(gCornerFinderOutputCorners);
        gCornerFinderOutputCorners = NULL;
    }
    gCornerFinderOutputFoundCount = 0;
    gCornerFinderOutputFoundAllFlag = 0;
    if (gCornerFinderOutputCVImage) cvReleaseImageHeader(&gCornerFinderOutputCVImage);
    if (gCornerFinderOutputImage) {
        free(gCornerFinderOutputImage);
        gCornerFinderOutputImage = NULL;
    }
    pthread_mutex_destroy(&gCornerFinderResultLock);
    
    // Clean up the corner finder.
    if (gCornerFinderThread) {
        
        threadWaitQuit(gCornerFinderThread);
        CORNER_FINDER_DATA_T *cornerFinderData = (CORNER_FINDER_DATA_T *)threadGetArg(gCornerFinderThread);
        
        if (cornerFinderData->calibImage) cvReleaseImageHeader(&(cornerFinderData->calibImage));
        free(cornerFinderData->videoFrame);
        
        // Free space for results.
        if (cornerFinderData->corners) {
            free(cornerFinderData->corners);
            cornerFinderData->corners = NULL;
        }
        cornerFinderData->cornerCount = 0;
        cornerFinderData->cornerFoundAllFlag = 0;
        threadFree(&gCornerFinderThread);
    }
    
    // Calibration input cleanup.
    free(gCorners);
    gCorners = NULL;
}


