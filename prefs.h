//
//  prefs.h
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 1/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#ifndef prefs_h
#define prefs_h

#ifdef __cplusplus
extern "C" {
#endif
    
void *initPreferences(void);
void showPreferences(void *preferences);
void preferencesFinal(void **preferences_p);

char *getPreferenceCameraOpenToken(void);
char *getPreferenceCalibrationServerUploadURL(void);
char *getPreferenceCalibrationServerAuthenticationToken(void);

#ifdef __cplusplus
}
#endif
#endif /* prefs_h */
