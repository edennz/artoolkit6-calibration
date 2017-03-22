/*
 *  Calibration.hpp
 *  ARToolKit6 Camera Calibration Utility
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
 *  Copyright 2015-2017 Daqri, LLC.
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
    Calibration(const int calibImageCountMax, const int chessboardCornerNumX, const int chessboardCornerNumY, const int chessboardSquareWidth, const int videoWidth, const int videoHeight);
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
    
    Calibration(const Calibration&) = delete;
    Calibration& operator=(const Calibration&) = delete;
    
    // This function runs the heavy-duty corner finding process on a secondary thread. Must be static so it can be
    // passed to threadInit().
    static void *cornerFinder(THREAD_HANDLE_T *threadHandle);
    
    // A class to encapsulate the inputs and outputs of a corner-finding run, and to allow for copying of the results
    // of a completed run.
    class CalibrationCornerFinderData {
    public:
        CalibrationCornerFinderData(const int chessboardCornerNumX_in, const int chessboardCornerNumY_in, const int videoWidth_in, const int videoHeight_in);
        CalibrationCornerFinderData(const CalibrationCornerFinderData& orig);
        const CalibrationCornerFinderData& operator=(const CalibrationCornerFinderData& orig);
        ~CalibrationCornerFinderData();
        int                  chessboardCornerNumX;
        int                  chessboardCornerNumY;
        int                  videoWidth;
        int                  videoHeight;
        uint8_t             *videoFrame;
        IplImage            *calibImage;
        int                  cornerFoundAllFlag;
        int                  cornerCount;
        CvPoint2D32f        *corners;
    private:
        void init();
        void copy(const CalibrationCornerFinderData& orig);
        void dealloc();
    };
    
    CalibrationCornerFinderData m_cornerFinderData; // Corner finder input and output.
    THREAD_HANDLE_T     *m_cornerFinderThread = NULL;
    pthread_mutex_t      m_cornerFinderResultLock;
    CalibrationCornerFinderData m_cornerFinderResultData; // Corner finder results copy, for display to user.
    
    CvPoint2D32f        *m_corners = NULL; // Collected corner information which gets passed to the OpenCV calibration function.
    int                  m_calibImageCount;
    int                  m_calibImageCountMax;
    int                  m_chessboardCornerNumX;
    int                  m_chessboardCornerNumY;
    int                  m_chessboardSquareWidth;
    int                  m_videoWidth;
    int                  m_videoHeight;
};
