//
//  prefsLibConfig.c
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 6/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//


#define _GNU_SOURCE

#include <AR6/AR/ar.h>
#if TARGET_PLATFORM_LINUX

#include <stdio.h>
#include "prefs.h"
#include <libconfig.h>
#include <Eden/EdenMessage.h>
#include <pthread.h>
#include <AR6/ARVideo/video.h>
#include "flow.h"

#define PREFS_FILENAME "prefs"

void *showPreferencesThread(void *);

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
    pthread_t pt;
    pthread_attr_t pta;
    
    pthread_attr_init(&pta);
    pthread_attr_setdetachstate(&pta, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&pt, &pta, showPreferencesThread, preferences) < 0) {
        ARLOGperror(NULL);
        return;
    }
    pthread_attr_destroy(&pta);
}

void *showPreferencesThread(void *arg)
{
    enum state {
        PREFS_BEGIN,
        PREFS_OPTION_1,
        PREFS_OPTION_2,
        PREFS_OPTION_3,
        PREFS_END
    };
    enum state state = PREFS_BEGIN;
    char defaultCalibrationServerURL[] = "https://omega.artoolworks.com/app/calib_camera/upload.php";
    char defaultCalibrationServerAuthenticationToken[] = "com.artoolworks.utils.calib_camera.116D5A95-E17B-266E-39E4-E5DED6C07C53";
    int inputi;
    unsigned char *inputa;
    
    flowHandleEvent(EVENT_MODAL);
    
    while (state != PREFS_END) {
        if (state == PREFS_BEGIN) {
            const char prompt[] = "Preferences\n\n1. Camera.\n2. Calibration server URL.\n3. Calibration server authentication token.\n\nType number and press [return] ";
            EdenMessageInput((const unsigned char *)prompt, 1, 1, 1, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_END;
            else if (!inputa[0] || sscanf((const char *)inputa, "%d", &inputi) < 1) {
                free(inputa);
                state = PREFS_END;
            } else {
                free(inputa);
                if (inputi == 1) state = PREFS_OPTION_1;
                else if (inputi == 2) state = PREFS_OPTION_2;
                else if (inputi == 3) state = PREFS_OPTION_3;
            }
        } else if (state == PREFS_OPTION_1) {
            ARVideoSourceInfoListT *sil = ar2VideoCreateSourceInfoList("");
            if (!sil) {
                ARLOGe("Unable to get ARVideoSourceInfoListT.\n");
                state = PREFS_END;
            } else if (sil->count == 0) {
                EdenMessageInput((const unsigned char *)"No video sources connected.\n\nPress [return] to continue.", 0, 1, 0, 0, 0);
                state = PREFS_BEGIN;
            } else {
                char prompt[4096] = "Preferences: Camera.\n\n";
                size_t len;
                for (int i = 0; i < sil->count; i++) {
                    len = strlen(prompt);
                    snprintf(prompt + len, sizeof(prompt) - len, "%d. %s\n", i + 1, sil->info[i].name);
                }
                len = strlen(prompt);
                snprintf(prompt + len, sizeof(prompt) - len, "Type number and press [return] ");
                EdenMessageInput((const unsigned char *)prompt, 1, 1, 1, 0, 0);
                inputa = EdenMessageInputGetInput();
                if (!inputa) state = PREFS_BEGIN;
                else if (!inputa[0] || sscanf((const char *)inputa, "%d", &inputi) < 1 || inputi < 1 || inputi > sil->count) {
                    free(inputa);
                } else {
                    ARLOGe("User chose camera %d (%s).\n", inputi - 1, sil->info[inputi - 1].open_token);
                }
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_2) {
            char prompt[4096] = "Preferences: Calibration server URL.\n\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current value is '%s'.\n\nPress [esc] to leave unchanged, [return] to use default setting '%s', or type new setting and press [return] ", "", defaultCalibrationServerURL);
            EdenMessageInput((const unsigned char *)prompt, 0, 2048, 0, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else if (!inputa[0]) {
                ARLOGe("User chose calibration server URL '%s'.\n", defaultCalibrationServerURL);
                free(inputa);
                state = PREFS_BEGIN;
            } else {
                ARLOGe("User chose calibration server URL '%s'.\n", inputa);
                free(inputa);
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_3) {
            char prompt[4096] = "Preferences: Calibration server authentication token.\n\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current value is '%s'.\n\nPress [esc] to leave unchanged, [return] to use default setting '%s', or type new setting and press [return] ", "", defaultCalibrationServerAuthenticationToken);
            EdenMessageInput((const unsigned char *)prompt, 0, 2048, 0, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else if (!inputa[0]) {
                ARLOGe("User chose calibration server authentication token '%s'.\n", defaultCalibrationServerAuthenticationToken);
                free(inputa);
                state = PREFS_BEGIN;
            } else {
                ARLOGe("User chose calibration server authentication token '%s'.\n", inputa);
                free(inputa);
                state = PREFS_BEGIN;
            }
        }
    }
    
    flowHandleEvent(EVENT_MODAL);
    
    return NULL;
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

#endif // TARGET_PLATFORM_LINUX
