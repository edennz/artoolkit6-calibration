/*
 *  prefsNull.cpp
 *  ARToolKit6
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
 *  Copyright 2017-2017 Daqri LLC. All Rights Reserved.
 *
 *  Author(s): Philip Lamb
 *
 */


#include <stdio.h>
#include <AR6/AR/config.h>
#include "prefs.hpp"

#if !TARGET_PLATFORM_MACOS && !TARGET_PLATFORM_LINUX && !TARGET_PLATFORM_IOS

void *initPreferences(void)
{
    return (NULL);
}

void preferencesFinal(void **preferences_p)
{
}

void showPreferences(void *preferences)
{
}

char *getPreferenceCameraOpenToken(void *preferences)
{
    return NULL;
}

char *getPreferenceCameraResolutionToken(void *preferences)
{
    return NULL;
}

char *getPreferenceCalibrationServerUploadURL(void *preferences)
{
    return strdup(CALIBRATION_SERVER_UPLOAD_URL_DEFAULT);
}

char *getPreferenceCalibrationServerAuthenticationToken(void *preferences)
{
    return strdup(CALIBRATION_SERVER_AUTHENTICATION_TOKEN_DEFAULT);
}

Calibration::CalibrationPatternType getPreferencesCalibrationPatternType(void *preferences)
{
    return CALIBRATION_PATTERN_TYPE_DEFAULT;
}

cv::Size getPreferencesCalibrationPatternSize(void *preferences)
{
    return Calibration::CalibrationPatternSizes[CALIBRATION_PATTERN_TYPE_DEFAULT];
}

float getPreferencesCalibrationPatternSpacing(void *preferences)
{
    return Calibration::CalibrationPatternSpacings[CALIBRATION_PATTERN_TYPE_DEFAULT];
}
#endif
