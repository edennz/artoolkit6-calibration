//
//  prefs.c
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 1/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#include <stdio.h>
#include <AR6/AR/config.h>
#include "prefs.h"

#if !TARGET_PLATFORM_MACOS && !TARGET_PLATFORM_LINUX

void *initPreferences(void)
{
    return (NULL);
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
    return NULL;
}

char *getPreferenceCalibrationServerAuthenticationToken(void *preferences)
{
    return NULL;
}

void preferencesFinal(void **preferences_p)
{
}

#endif // !TARGET_PLATFORM_MACOS
