/*
 *  Calibration.hpp
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

#pragma once

#include <AR6/AR/ar.h>
#include <opencv2/core/core.hpp>
#include <AR6/ARVideoSource.h>

#include <AR6/ARUtil/thread_sub.h>

class Calibration
{
public:
    //Calibration();
    bool init(const int calibImageCountMax, const int chessboardCornerNumX, const int chessboardCornerNumY, const int chessboardSquareWidth, const int videoWidth, const int videoHeight);
    int calibImageCount() const {return m_calibImageCount; }
    int calibImageCountMax() const {return m_calibImageCountMax; }
    bool frame(ARVideoSource *vs);
    bool cornerFinderResultsLockAndFetch(int *cornerFoundAllFlag, int *cornerCount, CvPoint2D32f **corners, ARUint8** videoFrame);
    bool cornerFinderResultsUnlock(void);
    bool capture();
    bool uncapture();
    void calib(ARParam *param_out, ARdouble *err_min_out, ARdouble *err_avg_out, ARdouble *err_max_out);
    ~Calibration();
    
private:
    
    static void *cornerFinder(THREAD_HANDLE_T *threadHandle);
    
    typedef struct {
        ARUint8*             videoFrame;
        IplImage            *calibImage;
        int                  chessboardCornerNumX;
        int                  chessboardCornerNumY;
        int                  cornerFoundAllFlag;
        int                  cornerCount;
        CvPoint2D32f        *corners;
    } CORNER_FINDER_DATA_T;
    
    // Corner finder.
    THREAD_HANDLE_T     *gCornerFinderThread = NULL;
    pthread_mutex_t      gCornerFinderResultLock;
    int                  gCornerFinderOutputFoundAllFlag = 0;
    int                  gCornerFinderOutputFoundCount = 0;
    CvPoint2D32f        *gCornerFinderOutputCorners = NULL;
    ARUint8*             gCornerFinderOutputImage = NULL; // The image to which gCornerFinderOutputCorners apply.
    IplImage            *gCornerFinderOutputCVImage;
    
    // Calibration inputs.
    CvPoint2D32f        *gCorners = NULL;
    int                  m_calibImageCount;
    int                  m_calibImageCountMax;
    int                  m_chessboardCornerNumX;
    int                  m_chessboardCornerNumY;
    int                  m_chessboardSquareWidth;
    int                  m_videoWidth;
    int                  m_videoHeight;
};
