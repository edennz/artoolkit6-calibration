/*
 *  fileUploader.h
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
 *  Copyright 2015-2016 Daqri LLC. All Rights Reserved.
 *  Copyright 2013-2015 ARToolworks, Inc. All Rights Reserved.
 *
 *  Author(s): Philip Lamb
 */


#ifndef FILEUPLOADER_H
#define FILEUPLOADER_H

//
// HTML form and file uploader via HTTP POST.
//
// When tickled, each index file in "queueDirPath" with extension "formExtension" will be opened
// and read for form data to be uploaded to URL "formPostURL" via HTTP POST.
// The format of the index file is 1 form field per line. From the beginning of the line up to
// the first ',' character is taken as the field name. The rest of the line after the ','
// up to the end-of-line is taken as the field contents.
// A field with the name 'file' is treated differently. If such a field is found, the field
// contents are taken as the pathname to a file to be uploaded. The file will be uploaded
// under a field named 'file', with its filename (not including any other path component)
// supplied as the filename portion of the field.
//
// Uses libcURL internally.
// Don't forget to add library load calls on the Java side:
//    static {
//    	System.loadLibrary("crypto");
//    	System.loadLibrary("ssl");
//    	System.loadLibrary("curl");
//    }
//

#include <sys/time.h> // struct timeval, gettimeofday(), timeradd()
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UPLOAD_STATUS_BUFFER_LEN 128

typedef struct _FILE_UPLOAD_HANDLE FILE_UPLOAD_HANDLE_t;

FILE_UPLOAD_HANDLE_t *fileUploaderInit(const char *queueDirPath, const char *formExtension, const char *formPostURL, const float statusHideAfterSecs);

void fileUploaderFinal(FILE_UPLOAD_HANDLE_t **handle_p);

// Check for existence of queue directory, and create if not already existing.
// Returns false if directory could not be created, true otherwise.
bool fileUploaderCreateQueueDir(FILE_UPLOAD_HANDLE_t *handle);

bool fileUploaderTickle(FILE_UPLOAD_HANDLE_t *handle);

// -2 = An error.
// 0 = no background tasks or messages.
// 1 = background task currently in progress.
// 2 = background task complete, message still to be shown.
int fileUploaderStatusGet(FILE_UPLOAD_HANDLE_t *handle, char statusBuf[UPLOAD_STATUS_BUFFER_LEN], struct timeval *currentTime_p);

#ifdef __cplusplus
}
#endif
#endif // !FILEUPLOADER_H
