//
//  prefsLibConfig.c
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 6/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//


#include <AR6/AR/ar.h>

//#if TARGET_PLATFORM_LINUX

#include <stdio.h>
#include "prefs.h"
#include <libconfig.h>

#define PREFS_FILENAME "prefs"

void *initPreferences(void)
{
    config_t *config_p;
    arMalloc(config_p, config_t, 1);
    config_init(config_p);
    
    char *prefsPath;
    if (asprintf(&prefsPath, "%s/%s", arUtilGetResourcesDirectoryPath(AR_UTIL_RESOURCES_DIRECTORY_BEHAVIOR_USE_APP_DATA_DIR), PREFS_FILENAME) < 0) {
        ARLOGperror(NULL);
        return NULL;
    }
    
    
    return (config_p);
}

void showPreferences(void *preferences)
{
}

char *getPreferenceCameraOpenToken(void)
{
    return NULL;
}

char *getPreferenceCameraResolutionToken(void)
{
    return NULL;
}

char *getPreferenceCalibrationServerUploadURL(void)
{
    return NULL;
}

char *getPreferenceCalibrationServerAuthenticationToken(void)
{
    return NULL;
}

void preferencesFinal(void **preferences_p)
{
    config_t *config_p = (config_t *)(*preferences_p);
    
    config_destroy(config_p);
    
    free(*preferences_p);
    *preferences_p = NULL;
}

//#endif // #include <AR6/AR/config.h>
