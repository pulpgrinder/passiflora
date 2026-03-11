let PassifloraMedia = {

    /**
     * Capture a screenshot of the app window.
     * Returns a one-time URL to a PNG image.
     */
    takeScreenshot: function () {
        return PassifloraIO._posixCall("takeScreenshot", {});
    },

    /**
     * List available cameras.
     * Returns an array of objects: [{id, name, position}, ...]
     * position is "front", "back", or "unspecified".
     */
    listCameras: function () {
        return PassifloraIO._posixCall("listCameras", {});
    },

    /**
     * Capture a still image from the specified camera.
     * cameraId: camera ID string from listCameras(), or:
     *   "0" / undefined  = default camera
     *   "front"          = front-facing camera
     *   "back"           = back-facing camera
     * Returns a one-time URL to a JPEG image.
     */
    captureImage: function (cameraId) {
        return PassifloraIO._posixCall("captureImage", {
            camera: cameraId || "0"
        });
    },

    /**
     * Begin recording audio from the default microphone.
     * Call stopAudioRecording() to finish.
     */
    startAudioRecording: function () {
        return PassifloraIO._posixCall("startAudioRecording", {});
    },

    /**
     * Stop an in-progress audio recording.
     */
    stopAudioRecording: function () {
        return PassifloraIO._posixCall("stopAudioRecording", {});
    },

    /**
     * Retrieve the most recent audio recording.
     * Returns a one-time URL to an M4A (AAC) file.
     * Call after stopAudioRecording().
     */
    getAudioRecording: function () {
        return PassifloraIO._posixCall("getAudioRecording", {});
    },

    /**
     * Begin recording video (and audio) from the specified camera.
     * cameraId: same rules as captureImage().
     * Call stopVideoRecording() to finish.
     */
    startVideoRecording: function (cameraId) {
        return PassifloraIO._posixCall("startVideoRecording", {
            camera: cameraId || "0"
        });
    },

    /**
     * Stop an in-progress video recording.
     */
    stopVideoRecording: function () {
        return PassifloraIO._posixCall("stopVideoRecording", {});
    },

    /**
     * Retrieve the most recent video recording.
     * Returns a one-time URL to a MOV file.
     * Call after stopVideoRecording().
     */
    getVideoRecording: function () {
        return PassifloraIO._posixCall("getVideoRecording", {});
    }
}