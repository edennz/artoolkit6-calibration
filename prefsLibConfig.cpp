/*
 *  prefsLibConfig.cpp
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


#ifndef _GNU_SOURCE
#  define _GNU_SOURCE
#endif

#include <AR6/AR/ar.h>
#if TARGET_PLATFORM_LINUX

#include <stdio.h>
#include "prefs.hpp"
#include <libconfig.h>
#include <Eden/EdenMessage.h>
#include <pthread.h>
#include <AR6/ARVideo/video.h>
#include "flow.hpp"
#include <AR6/ARUtil/file_utils.h>
#include "calib_camera.h"

#define PREFS_FILENAME "prefs"

typedef struct {
    char *prefsPath;
    config_t config;
    config_setting_t *settingCOT;
    config_setting_t *settingCSUU;
    config_setting_t *settingCSAT;
    config_setting_t *settingCalibrationPatternType;
    config_setting_t *settingCalibrationPatternSizeWidth;
    config_setting_t *settingCalibrationPatternSizeHeight;
    config_setting_t *settingCalibrationPatternSpacing;
} prefsLibConfig_t;

static const char *kSettingCameraOpenToken = "cameraOpenToken";
static const char *kSettingCalibrationServerUploadURL = "calibrationServerUploadURL";
static const char *kSettingCalibrationServerAuthenticationToken = "calibrationServerAuthenticationToken";
static const char *kSettingCalibrationPatternType = "calibrationPatternType";
static const char *kSettingCalibrationPatternSizeWidth = "calibrationPatternSizeWidth";
static const char *kSettingCalibrationPatternSizeHeight = "calibrationPatternSizeHeight";
static const char *kSettingCalibrationPatternSpacing = "calibrationPatternSpacing";

static const char *kCalibrationPatternTypeChessboardStr = "Chessboard";
static const char *kCalibrationPatternTypeCirclesStr = "Circles";
static const char *kCalibrationPatternTypeAsymmetricCirclesStr = "Asymmetric circles";

void *showPreferencesThread(void *);

void *initPreferences(void)
{
    prefsLibConfig_t *prefs;
    int err;
    
    arMallocClear(prefs, prefsLibConfig_t, 1);
    config_init(&prefs->config);
    config_setting_t *root = config_root_setting(&prefs->config);
    
    if (asprintf(&prefs->prefsPath, "%s/%s", arUtilGetAndCreateResourcesDirectoryPath(AR_UTIL_RESOURCES_DIRECTORY_BEHAVIOR_USE_APP_DATA_DIR), PREFS_FILENAME) < 0) {
        ARLOGperror(NULL);
        goto bail;
    }
    ARLOGd("Preferences config path is '%s'.\n", prefs->prefsPath);
    
    // Attempt to read config, initialising any unconfigured values to defaults.
    err = test_f(prefs->prefsPath, NULL);
    if (err < 0) {
        ARLOGperror(NULL);
        goto bail;
    } else if (err == 0) {
        // Ensure that the directory is available.
        
    } else if (err == 1) {
        if (config_read_file(&prefs->config, prefs->prefsPath) == CONFIG_FALSE) {
            ARLOGe("Error reading configuration file '%s': %s.\n", prefs->prefsPath, config_error_text(&prefs->config));
            goto bail;
        }
        prefs->settingCOT = config_setting_get_member(root, kSettingCameraOpenToken);
        prefs->settingCSUU = config_setting_get_member(root, kSettingCalibrationServerUploadURL);
        prefs->settingCSAT = config_setting_get_member(root, kSettingCalibrationServerAuthenticationToken);
        prefs->settingCalibrationPatternType = config_setting_get_member(root, kSettingCalibrationPatternType);
        prefs->settingCalibrationPatternSizeWidth = config_setting_get_member(root, kSettingCalibrationPatternSizeWidth);
        prefs->settingCalibrationPatternSizeHeight = config_setting_get_member(root, kSettingCalibrationPatternSizeHeight);
        prefs->settingCalibrationPatternSpacing = config_setting_get_member(root, kSettingCalibrationPatternSpacing);
    }
    if (!prefs->settingCOT) prefs->settingCOT = config_setting_add(root, kSettingCameraOpenToken, CONFIG_TYPE_STRING);
    if (!prefs->settingCSUU) prefs->settingCSUU = config_setting_add(root, kSettingCalibrationServerUploadURL, CONFIG_TYPE_STRING);
    if (!prefs->settingCSAT) prefs->settingCSAT = config_setting_add(root, kSettingCalibrationServerAuthenticationToken, CONFIG_TYPE_STRING);
    if (!prefs->settingCalibrationPatternType) prefs->settingCalibrationPatternType = config_setting_add(root, kSettingCalibrationPatternType, CONFIG_TYPE_STRING);
    if (!prefs->settingCalibrationPatternSizeWidth) prefs->settingCalibrationPatternSizeWidth = config_setting_add(root, kSettingCalibrationPatternSizeWidth, CONFIG_TYPE_INT);
    if (!prefs->settingCalibrationPatternSizeHeight) prefs->settingCalibrationPatternSizeHeight = config_setting_add(root, kSettingCalibrationPatternSizeHeight, CONFIG_TYPE_INT);
    if (!prefs->settingCalibrationPatternSpacing) prefs->settingCalibrationPatternSpacing = config_setting_add(root, kSettingCalibrationPatternSpacing, CONFIG_TYPE_FLOAT);
    
    return ((void *)prefs);
    
bail:
    free(prefs);
    return (NULL);
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
        PREFS_OPTION_4,
        PREFS_OPTION_5,
        PREFS_OPTION_6,
        PREFS_END
    };
    enum state state = PREFS_BEGIN;
    int inputi;
    unsigned char *inputa;
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)arg;
    
    if (!prefs) {
        ARLOGe("NULL preferences.\n");
        return (NULL);
    }
    
    flowHandleEvent(EVENT_MODAL);
    
    while (state != PREFS_END) {
        if (state == PREFS_BEGIN) {
            const char prompt[] =
                "Preferences\n"
                "\n"
                "1. Camera.\n"
                "2. Calibration server URL.\n"
                "3. Calibration server authentication token.\n"
                "4. Calibration pattern type.\n"
                "5. Calibration pattern size.\n"
                "6. Calibration pattern spacing.\n"
                "\n"
                "Press [esc] to finish or type number and press [return] ";
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
                else if (inputi == 4) state = PREFS_OPTION_4;
                else if (inputi == 5) state = PREFS_OPTION_5;
                else if (inputi == 6) state = PREFS_OPTION_6;
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
                int selectedItemIndex = -1;
                const char *cot = config_setting_get_string(prefs->settingCOT);
                for (int i = 0; i < sil->count; i++) {
                    len = strlen(prompt);
                    snprintf(prompt + len, sizeof(prompt) - len, "%d. %s\n", i + 1, sil->info[i].name);
                    if (cot && sil->info[i].open_token && strcmp(cot, sil->info[i].open_token) == 0) {
                        selectedItemIndex = i;
                    }
                }
                len = strlen(prompt);
                snprintf(prompt + len, sizeof(prompt) - len, "\nCurrent value is %s.\n\nPress [esc] to leave unchanged, or type a number and press [return] ", (selectedItemIndex >= 0 ? sil->info[selectedItemIndex].name : "a camera not currently connected"));
                EdenMessageInput((const unsigned char *)prompt, 1, 1, 1, 0, 0);
                inputa = EdenMessageInputGetInput();
                if (!inputa) state = PREFS_BEGIN;
                else if (!inputa[0] || sscanf((const char *)inputa, "%d", &inputi) < 1 || inputi < 1 || inputi > sil->count) {
                    free(inputa);
                } else {
                    config_setting_set_string(prefs->settingCOT, sil->info[inputi - 1].open_token);
                    ARLOGd("User chose camera %d (%s).\n", inputi - 1, sil->info[inputi - 1].open_token);
                }
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_2) {
            const char *s = config_setting_get_string(prefs->settingCSUU);
            char prompt[4096] = "Preferences: Calibration server URL.\n\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current value is '%s'.\n\nPress [esc] to leave unchanged, [return] to use default, or type new setting and press [return] ", s ? s : "");
            EdenMessageInput((const unsigned char *)prompt, 0, 2048, 0, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else {
                if (inputa[0]) {
                    config_setting_set_string(prefs->settingCSUU, (const char *)inputa);
                    ARLOGd("User chose calibration server upload URL '%s'.\n", (const char *)inputa);
                }
                free(inputa);
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_3) {
            const char *s = config_setting_get_string(prefs->settingCSAT);
            char prompt[4096] = "Preferences: Calibration server authentication token.\n\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current value is '%s'.\n\nPress [esc] to leave unchanged, [return] to use default, or type new setting and press [return] ", s ? s : "");
            EdenMessageInput((const unsigned char *)prompt, 0, 2048, 0, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else {
                if (inputa[0]) {
                    config_setting_set_string(prefs->settingCSAT, (const char *)inputa);
                    ARLOGd("User chose calibration server authentication token '%s'.\n", (const char *)inputa);
                }
                free(inputa);
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_4) {
            const char *s = config_setting_get_string(prefs->settingCalibrationPatternType);
            char prompt[4096] = "Preferences: Calibration pattern type.\n\n1. Chessboard\n2. Circles\n3. Asymmetric circles.\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current value is '%s'.\n\nPress [esc] to leave unchanged, or type a number and press [return] ", s ? s : "");
            EdenMessageInput((const unsigned char *)prompt, 1, 1, 1, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else if (!inputa[0] || sscanf((const char *)inputa, "%d", &inputi) < 1) {
                free(inputa);
                state = PREFS_BEGIN;
            } else {
                free(inputa);
                const char *typeA = NULL;
                Calibration::CalibrationPatternType type;
                if (inputi == 1) {
                    typeA = kCalibrationPatternTypeChessboardStr;
                    type = Calibration::CalibrationPatternType::CHESSBOARD;
                } else if (inputi == 2) {
                    typeA = kCalibrationPatternTypeCirclesStr;
                    type = Calibration::CalibrationPatternType::CIRCLES_GRID;
                } else if (inputi == 3) {
                    typeA = kCalibrationPatternTypeAsymmetricCirclesStr;
                    type = Calibration::CalibrationPatternType::ASYMMETRIC_CIRCLES_GRID;
                }
                if (typeA) {
                    config_setting_set_string(prefs->settingCalibrationPatternType, typeA);
                    config_setting_set_int(prefs->settingCalibrationPatternSizeWidth, Calibration::CalibrationPatternSizes[type].width);
                    config_setting_set_int(prefs->settingCalibrationPatternSizeHeight, Calibration::CalibrationPatternSizes[type].height);
                    config_setting_set_float(prefs->settingCalibrationPatternSpacing,  Calibration::CalibrationPatternSpacings[type]);
                    ARLOGd("User chose calibration pattern type '%s'.\n", type);
                }
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_5) {
            int w = config_setting_get_int(prefs->settingCalibrationPatternSizeWidth);
            int h = config_setting_get_int(prefs->settingCalibrationPatternSizeHeight);
            char prompt[4096] = "Preferences: Calibration pattern size.\n\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current size is %dx%d.\n\nPress [esc] to leave unchanged, or type new values and press [return] ", w, h);
            EdenMessageInput((const unsigned char *)prompt, 1, 7, 0, 0, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else if (!inputa[0] || sscanf((const char *)inputa, "%dx%d", &w, &h) < 2) {
                free(inputa);
                state = PREFS_BEGIN;
            } else {
                free(inputa);
                config_setting_set_int(prefs->settingCalibrationPatternSizeWidth, w);
                config_setting_set_int(prefs->settingCalibrationPatternSizeHeight, h);
                ARLOGd("User chose calibration pattern size %dx%d.\n", w, h);
                state = PREFS_BEGIN;
            }
        } else if (state == PREFS_OPTION_6) {
            float f = config_setting_get_float(prefs->settingCalibrationPatternSpacing);
            char prompt[4096] = "Preferences: Calibration pattern spacing.\n\n";
            size_t len;
            len = strlen(prompt);
            snprintf(prompt + len, sizeof(prompt) - len, "Current spacing is %.2f.\n\nPress [esc] to leave unchanged, or type new value and press [return] ", f);
            EdenMessageInput((const unsigned char *)prompt, 1, 20, 0, 1, 0);
            inputa = EdenMessageInputGetInput();
            if (!inputa) state = PREFS_BEGIN;
            else if (!inputa[0] || sscanf((const char *)inputa, "%f", &f) < 1) {
                free(inputa);
                state = PREFS_BEGIN;
            } else {
                free(inputa);
                config_setting_set_float(prefs->settingCalibrationPatternSpacing, f);
                ARLOGd("User chose calibration pattern spacing %.2f.\n", f);
                state = PREFS_BEGIN;
            }
        }
    }
    
    if (config_write_file(&prefs->config, prefs->prefsPath) == CONFIG_FALSE) {
        ARLOGe("Error writing configuration file '%s': %s.\n", prefs->prefsPath, config_error_text(&prefs->config));
    }
        
    flowHandleEvent(EVENT_MODAL);
    
    SDL_Event event;
    SDL_zero(event);
    event.type = gSDLEventPreferencesChanged;
    event.user.code = (Sint32)0;
    event.user.data1 = NULL;
    event.user.data2 = NULL;
    SDL_PushEvent(&event);

    return NULL;
}

char *getPreferenceCameraOpenToken(void *preferences)
{
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return NULL;
    
    const char *s = config_setting_get_string(prefs->settingCOT);
    if (s && s[0]) return strdup(s);
    return NULL;
}

char *getPreferenceCameraResolutionToken(void *preferences)
{
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return NULL;
    
    return NULL;
}

char *getPreferenceCalibrationServerUploadURL(void *preferences)
{
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return NULL;
    
    const char *s = config_setting_get_string(prefs->settingCSUU);
    if (s && s[0]) return strdup(s);
    return (strdup(CALIBRATION_SERVER_UPLOAD_URL_DEFAULT));
}

char *getPreferenceCalibrationServerAuthenticationToken(void *preferences)
{
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return NULL;
    
    const char *s = config_setting_get_string(prefs->settingCSAT);
    if (s && s[0]) return strdup(s);
    return (strdup(CALIBRATION_SERVER_AUTHENTICATION_TOKEN_DEFAULT));
}

Calibration::CalibrationPatternType getPreferencesCalibrationPatternType(void *preferences)
{
    Calibration::CalibrationPatternType patternType = CALIBRATION_PATTERN_TYPE_DEFAULT;
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return patternType;
    
    const char *s = config_setting_get_string(prefs->settingCalibrationPatternType);
    if (s && s[0]) {
        if (strcmp(s, kCalibrationPatternTypeChessboardStr) == 0) patternType = Calibration::CalibrationPatternType::CHESSBOARD;
        else if (strcmp(s, kCalibrationPatternTypeCirclesStr) == 0) patternType = Calibration::CalibrationPatternType::CIRCLES_GRID;
        else if (strcmp(s, kCalibrationPatternTypeAsymmetricCirclesStr) == 0) patternType = Calibration::CalibrationPatternType::ASYMMETRIC_CIRCLES_GRID;
    }

    return patternType;
}

cv::Size getPreferencesCalibrationPatternSize(void *preferences)
{
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return Calibration::CalibrationPatternSizes[CALIBRATION_PATTERN_TYPE_DEFAULT];
    
    int w = config_setting_get_int(prefs->settingCalibrationPatternSizeWidth);
    int h = config_setting_get_int(prefs->settingCalibrationPatternSizeHeight);
    if (w > 0 && h > 0) return cv::Size(w, h);
    return Calibration::CalibrationPatternSizes[CALIBRATION_PATTERN_TYPE_DEFAULT];
}

float getPreferencesCalibrationPatternSpacing(void *preferences)
{
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)preferences;
    if (!prefs) return Calibration::CalibrationPatternSpacings[CALIBRATION_PATTERN_TYPE_DEFAULT];
    
    float f = config_setting_get_int(prefs->settingCalibrationPatternSpacing);
    if (f > 0.0f) return f;
    
    return Calibration::CalibrationPatternSpacings[CALIBRATION_PATTERN_TYPE_DEFAULT];
}

void preferencesFinal(void **preferences_p)
{
    if (!preferences_p) return;
    prefsLibConfig_t *prefs = (prefsLibConfig_t *)*preferences_p;
    if (!prefs) return;
    
    config_destroy(&prefs->config);
    free(prefs->prefsPath);

    free(*preferences_p);
    *preferences_p = NULL;
}

#endif // TARGET_PLATFORM_LINUX
