//
//  prefs.h
//  ARToolKit6 Camera Calibration Utility
//
//  Created by Philip Lamb on 1/03/17.
//  Copyright © 2017 artoolkit.org. All rights reserved.
//

#ifndef prefs_h
#define prefs_h

// Data upload.
#define CALIBRATION_SERVER_UPLOAD_URL_DEFAULT "https://omega.artoolworks.com/app/calib_camera/upload.php"
// Until we implement nonce-based hashing, use of the plain md5 of the calibration server authentication token is vulnerable to replay attack.
// The calibration server authentication token itself needs to be hidden in the binary.
#define CALIBRATION_SERVER_AUTHENTICATION_TOKEN_DEFAULT "com.artoolworks.utils.calib_camera.116D5A95-E17B-266E-39E4-E5DED6C07C53" // MD5 = {0x32, 0x57, 0x5a, 0x6f, 0x69, 0xa4, 0x11, 0x5a, 0x25, 0x49, 0xae, 0x55, 0x6b, 0xd2, 0x2a, 0xda}


#ifdef __cplusplus
extern "C" {
#endif

void *initPreferences(void);
void showPreferences(void *preferences);
void preferencesFinal(void **preferences_p);

char *getPreferenceCameraOpenToken(void *preferences);
char *getPreferenceCameraResolutionToken(void *preferences);
char *getPreferenceCalibrationServerUploadURL(void *preferences);
char *getPreferenceCalibrationServerAuthenticationToken(void *preferences);

#ifdef __cplusplus
}
#endif
#endif /* prefs_h */
