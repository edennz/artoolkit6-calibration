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

Calibration::CalibrationCornerFinderData::CalibrationCornerFinderData(const int chessboardCornerNumX_in, const int chessboardCornerNumY_in, const int videoWidth_in, const int videoHeight_in) :
    chessboardCornerNumX(chessboardCornerNumX_in),
    chessboardCornerNumY(chessboardCornerNumY_in),
    videoWidth(videoWidth_in),
    videoHeight(videoHeight_in),
    cornerFoundAllFlag(0),
    cornerCount(0)
{
    init();
}

Calibration::CalibrationCornerFinderData::CalibrationCornerFinderData(const CalibrationCornerFinderData& orig) :
    chessboardCornerNumX(orig.chessboardCornerNumX),
    chessboardCornerNumY(orig.chessboardCornerNumY),
    videoWidth(orig.videoWidth),
    videoHeight(orig.videoHeight),
    cornerFoundAllFlag(orig.cornerFoundAllFlag),
    cornerCount(orig.cornerCount)
{
    init();
    copy(orig);
}

const Calibration::CalibrationCornerFinderData& Calibration::CalibrationCornerFinderData::operator=(const Calibration::CalibrationCornerFinderData::CalibrationCornerFinderData& orig)
{
    if (this != &orig) {
        dealloc();
        chessboardCornerNumX = orig.chessboardCornerNumX;
        chessboardCornerNumY = orig.chessboardCornerNumY;
        videoWidth = orig.videoWidth;
        videoHeight = orig.videoHeight;
        cornerFoundAllFlag = orig.cornerFoundAllFlag;
        cornerCount = orig.cornerCount;
        init();
        copy(orig);
    }
    return *this;
}

Calibration::CalibrationCornerFinderData::~CalibrationCornerFinderData()
{
    dealloc();
}

void Calibration::CalibrationCornerFinderData::init()
{
    if (chessboardCornerNumX > 0 && chessboardCornerNumY > 0) {
        arMalloc(corners, CvPoint2D32f, chessboardCornerNumX * chessboardCornerNumY);
    } else {
        corners = nullptr;
    }
    if (videoWidth > 0 && videoHeight > 0) {
        arMalloc(videoFrame, uint8_t, videoWidth * videoHeight);
        calibImage = cvCreateImageHeader(cvSize(videoWidth, videoHeight), IPL_DEPTH_8U, 1);
        cvSetData(calibImage, videoFrame, videoWidth); // Last parameter is rowBytes.
    } else {
        videoFrame = nullptr;
        calibImage = nullptr;
    }
}

void Calibration::CalibrationCornerFinderData::copy(const CalibrationCornerFinderData& orig)
{
    memcpy(corners, orig.corners, sizeof(CvPoint2D32f) * chessboardCornerNumX * chessboardCornerNumY);
    memcpy(videoFrame, orig.videoFrame, sizeof(uint8_t) * videoWidth * videoHeight);
}

void Calibration::CalibrationCornerFinderData::dealloc()
{
    if (calibImage) cvReleaseImageHeader(&calibImage);
    free(videoFrame);
    free(corners);
}


Calibration::Calibration(const int calibImageCountMax, const int chessboardCornerNumX, const int chessboardCornerNumY, const int chessboardSquareWidth, const int videoWidth, const int videoHeight) :
    m_cornerFinderData(chessboardCornerNumX, chessboardCornerNumY, videoWidth, videoHeight),
    m_cornerFinderResultData(0, 0, 0, 0),
    m_calibImageCount(0),
    m_calibImageCountMax(calibImageCountMax),
    m_chessboardCornerNumX(chessboardCornerNumX),
    m_chessboardCornerNumY(chessboardCornerNumY),
    m_chessboardSquareWidth(chessboardSquareWidth),
    m_videoWidth(videoWidth),
    m_videoHeight(videoHeight)
{
    arMalloc(m_corners, CvPoint2D32f, chessboardCornerNumX*chessboardCornerNumY*calibImageCountMax);
    
    // Spawn the corner finder worker thread.
    m_cornerFinderThread = threadInit(0, (void *)(&m_cornerFinderData), cornerFinder);
    
    pthread_mutex_init(&m_cornerFinderResultLock, NULL);
}

bool Calibration::frame(ARVideoSource *vs)
{
    //
    // Start of main calibration-related cycle.
    //
    
    // First, see if an image has been completely processed.
    if (threadGetStatus(m_cornerFinderThread)) {
        threadEndWait(m_cornerFinderThread); // We know from status above that worker has already finished, so this just resets it.
        ARLOGd("processFrame: corner find DONE.\n");
        
        // Copy the results.
        pthread_mutex_lock(&m_cornerFinderResultLock); // Results are also read by GL thread, so need to lock before modifying.
        m_cornerFinderResultData = m_cornerFinderData;
        pthread_mutex_unlock(&m_cornerFinderResultLock);
    }
    
    // If corner finder worker thread is ready and waiting, submit the new image.
    if (!threadGetBusyStatus(m_cornerFinderThread)) {
        // As corner finding takes longer than a single frame capture, we need to copy the incoming image
        // so that OpenCV has exclusive use of it. We copy into cornerFinderData->videoFrame which provides
        // the backing for calibImage.
        AR2VideoBufferT *buff = vs->checkoutFrameIfNewerThan({0,0});
        if (buff) {
            memcpy(m_cornerFinderData.videoFrame, buff->buffLuma, vs->getVideoWidth()*vs->getVideoHeight());
            vs->checkinFrame();
            
            // Kick off a new cycle of the cornerFinder. The results will be collected on a subsequent cycle.
            ARLOGd("processFrame: corner find GO\n");
            threadStartSignal(m_cornerFinderThread);
        }
    }
    
    //
    // End of main calibration-related cycle.
    //
    return true;
}

bool Calibration::cornerFinderResultsLockAndFetch(int *cornerFoundAllFlag, int *cornerCount, CvPoint2D32f **corners, ARUint8** videoFrame)
{
    pthread_mutex_lock(&m_cornerFinderResultLock);
    *cornerFoundAllFlag = m_cornerFinderResultData.cornerFoundAllFlag;
    *cornerCount = m_cornerFinderResultData.cornerCount;
    *corners = m_cornerFinderResultData.corners;
    *videoFrame = m_cornerFinderResultData.videoFrame;
    return true;
}

bool Calibration::cornerFinderResultsUnlock(void)
{
    pthread_mutex_unlock(&m_cornerFinderResultLock);
    return true;
}

// Worker thread.
// static
void *Calibration::cornerFinder(THREAD_HANDLE_T *threadHandle)
{
#ifdef DEBUG
    ARLOGi("Start cornerFinder thread.\n");
#endif
    
    CalibrationCornerFinderData *cornerFinderDataPtr = (CalibrationCornerFinderData *)threadGetArg(threadHandle);
    
    while (threadStartWait(threadHandle) == 0) {
        
        cornerFinderDataPtr->cornerFoundAllFlag = cvFindChessboardCorners(cornerFinderDataPtr->calibImage,
                                                                  cvSize(cornerFinderDataPtr->chessboardCornerNumY, cornerFinderDataPtr->chessboardCornerNumX),
                                                                  cornerFinderDataPtr->corners,
                                                                  &(cornerFinderDataPtr->cornerCount),
                                                                  CV_CALIB_CB_FAST_CHECK|CV_CALIB_CB_ADAPTIVE_THRESH|CV_CALIB_CB_FILTER_QUADS);
        ARLOGd("cornerFinderDataPtr->cornerFoundAllFlag=%d.\n", cornerFinderDataPtr->cornerFoundAllFlag);
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
    
    pthread_mutex_lock(&m_cornerFinderResultLock);
    if (m_cornerFinderResultData.cornerFoundAllFlag) {
        ARLOGd("Got all corners.\n");
        // Refine the corner positions.
        cvFindCornerSubPix(m_cornerFinderResultData.calibImage,
                           m_cornerFinderResultData.corners,
                           m_chessboardCornerNumX*m_chessboardCornerNumY,
                           cvSize(5,5),
                           cvSize(-1,-1),
                           cvTermCriteria(CV_TERMCRIT_ITER, 100, 0.1)  );
        
        // Save the corners.
        p1 = m_cornerFinderResultData.corners;
        p2 = &m_corners[m_calibImageCount * m_chessboardCornerNumX * m_chessboardCornerNumY];
        for (i = 0; i < m_chessboardCornerNumX * m_chessboardCornerNumY; i++) {
            *(p2++) = *(p1++);
        }
        saved = true;
    } else {
        ARLOGd("NOT got all corners.\n");
    }
    pthread_mutex_unlock(&m_cornerFinderResultLock);

    if (saved) {
        ARLOG("---------- %2d/%2d -----------\n", m_calibImageCount + 1, m_calibImageCountMax);
        for (i = 0; i < m_chessboardCornerNumX*m_chessboardCornerNumY; i++) {
            ARLOG("  %f, %f\n", m_corners[m_calibImageCount*m_chessboardCornerNumX*m_chessboardCornerNumY + i].x, m_corners[m_calibImageCount*m_chessboardCornerNumX*m_chessboardCornerNumY + i].y);
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
    calc(m_calibImageCount, m_chessboardCornerNumX, m_chessboardCornerNumY, m_chessboardSquareWidth, m_corners, m_videoWidth, m_videoHeight, param_out, err_min_out, err_avg_out, err_max_out);
}

Calibration::~Calibration()
{
    pthread_mutex_destroy(&m_cornerFinderResultLock);
    
    // Clean up the corner finder.
    if (m_cornerFinderThread) {
        
        threadWaitQuit(m_cornerFinderThread);
        threadFree(&m_cornerFinderThread);
    }
    
    // Calibration input cleanup.
    free(m_corners);
    m_corners = NULL;
}


