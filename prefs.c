//
//  prefs.c
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 1/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#include <stdio.h>

#if !TARGET_PLATFORM_MACOS

void *initPreferences(void)
{
    return (NULL);
}

void showPreferences(void *preferences)
{
}

char *getPreferenceCameraOpenToken(void)
{
    return NULL;
}

char *getPreferenceCalibrationServerURL(void)
{
    return NULL;
}

char *getPreferenceCalibrationServerAuthenticationToken(void)
{
    return NULL;
}

void preferencesFinal(void **preferences_p)
{
}

#endif // !TARGET_PLATFORM_MACOS
