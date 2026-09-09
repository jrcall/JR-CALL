// ===============================================================
// JR CALL
// File: MainActivity.kt
// Location:
// android/app/src/main/kotlin/com/example/jr_call/MainActivity.kt
//
// PRODUCTION ANDROID CALL PRESENTATION BRIDGE
//
// FIX:
// - Flutter MethodChannel launch actions are buffered before the
//   Dart BackgroundCallService handler is registered.
// - This prevents cold-start Accept/Reject actions from being lost.
// ===============================================================

package com.example.jr_call

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME =
            "jr_call/background_call"

        private const val INCOMING_CHANNEL_ID =
            "jr_call_incoming_calls"

        private const val INCOMING_CHANNEL_NAME =
            "JR CALL Incoming Calls"

        private const val ACTIVE_CHANNEL_ID =
            "jr_call_active_calls"

        private const val ACTIVE_CHANNEL_NAME =
            "JR CALL Active Calls"

        private const val INCOMING_NOTIFICATION_ID =
            41001

        private const val ACTIVE_NOTIFICATION_ID =
            41002

        private const val PREFS_NAME =
            "jr_call_background_call"

        private const val PREF_PENDING_CALL =
            "pending_call"

        private const val EXTRA_CALL_ID =
            "jr_call_call_id"

        private const val EXTRA_CALL_ACTION =
            "jr_call_action"

        private const val ACTION_OPEN =
            "open"

        private const val ACTION_ACCEPT =
            "accept"

        private const val ACTION_REJECT =
            "reject"

        private const val PERMISSION_USE_FULL_SCREEN_INTENT =
            "android.permission.USE_FULL_SCREEN_INTENT"
    }

    private var methodChannel: MethodChannel? = null

    private var flutterEngineReady = false

    private var lastDeliveredActionKey: String? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannels()

        val channel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL_NAME
            )

        // =======================================================
        // CRITICAL COLD-START FIX
        //
        // Android can create MainActivity and deliver the
        // notification Accept intent before Dart has installed
        // BackgroundCallService.setMethodCallHandler().
        //
        // Without this buffer the native method call can be
        // discarded. Flutter officially provides this API for
        // exactly this channel-startup condition.
        // =======================================================
        channel.resizeChannelBuffer(8)

        channel.setMethodCallHandler { call, result ->
            handleFlutterMethod(
                call = call,
                result = result
            )
        }

        methodChannel = channel

        flutterEngineReady = true

        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        handleLaunchIntent(intent)
    }

    private fun handleFlutterMethod(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {

                "initializeBackgroundCallService" -> {
                    createNotificationChannels()

                    result.success(true)
                }

                "showIncomingCall" -> {
                    val payload =
                        normalizeArguments(
                            call.arguments
                        )

                    val callId =
                        readString(
                            payload["callId"]
                        )

                    val callerId =
                        readString(
                            payload["callerId"]
                                ?: payload["senderId"]
                        )

                    val receiverId =
                        readString(
                            payload["receiverId"]
                                ?: payload["recipientId"]
                        )

                    if (
                        callId == null ||
                        callerId == null ||
                        receiverId == null
                    ) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "callId, callerId and receiverId are required.",
                            null
                        )

                        return
                    }

                    savePendingCall(payload)

                    val posted =
                        showIncomingCallNotification(
                            payload
                        )

                    result.success(posted)
                }

                "setCallConnecting" -> {
                    val payload =
                        normalizeArguments(
                            call.arguments
                        )

                    val callId =
                        readString(
                            payload["callId"]
                        )

                    if (callId != null) {
                        cancelIncomingNotification()

                        showActiveCallNotification(
                            callId = callId,
                            title = "Connecting",
                            body = "JR CALL is connecting…"
                        )
                    }

                    result.success(true)
                }

                "setCallOngoing" -> {
                    val payload =
                        normalizeArguments(
                            call.arguments
                        )

                    val callId =
                        readString(
                            payload["callId"]
                        )

                    if (callId != null) {
                        cancelIncomingNotification()

                        showActiveCallNotification(
                            callId = callId,
                            title = "JR CALL",
                            body = "Call in progress"
                        )
                    }

                    clearPendingCall()

                    result.success(true)
                }

                "dismissIncomingCall" -> {
                    cancelIncomingNotification()

                    clearPendingCall()

                    result.success(true)
                }

                "endNativeCall" -> {
                    cancelIncomingNotification()

                    cancelActiveNotification()

                    clearPendingCall()

                    result.success(true)
                }

                "getPendingCall" -> {
                    result.success(
                        loadPendingCall()
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        } catch (error: Throwable) {
            result.error(
                "JR_CALL_NATIVE_ERROR",
                error.message
                    ?: "Native call operation failed.",
                null
            )
        }
    }

    private fun showIncomingCallNotification(
        payload: Map<String, Any?>
    ): Boolean {

        val callId =
            readString(
                payload["callId"]
            ) ?: return false

        if (!canPostNotifications()) {
            return false
        }

        val callerName =
            readString(
                payload["callerName"]
            )
                ?: readString(
                    payload["senderName"]
                )
                ?: "JR CALL User"

        val isVideoCall =
            readBoolean(
                payload["isVideoCall"]
            )

        val openIntent =
            createCallIntent(
                callId = callId,
                action = ACTION_OPEN
            )

        val openPendingIntent =
            PendingIntent.getActivity(
                this,
                requestCode(
                    callId = callId,
                    suffix = 1
                ),
                openIntent,
                pendingIntentFlags()
            )

        val acceptIntent =
            createCallIntent(
                callId = callId,
                action = ACTION_ACCEPT
            )

        val acceptPendingIntent =
            PendingIntent.getActivity(
                this,
                requestCode(
                    callId = callId,
                    suffix = 2
                ),
                acceptIntent,
                pendingIntentFlags()
            )

        val rejectIntent =
            createCallIntent(
                callId = callId,
                action = ACTION_REJECT
            )

        val rejectPendingIntent =
            PendingIntent.getActivity(
                this,
                requestCode(
                    callId = callId,
                    suffix = 3
                ),
                rejectIntent,
                pendingIntentFlags()
            )

        val builder =
            NotificationCompat.Builder(
                this,
                INCOMING_CHANNEL_ID
            )
                .setSmallIcon(
                    applicationInfo.icon
                )
                .setContentTitle(
                    if (isVideoCall) {
                        "Incoming Video Call"
                    } else {
                        "Incoming Voice Call"
                    }
                )
                .setContentText(
                    "$callerName is calling you"
                )
                .setCategory(
                    NotificationCompat.CATEGORY_CALL
                )
                .setPriority(
                    NotificationCompat.PRIORITY_MAX
                )
                .setVisibility(
                    NotificationCompat.VISIBILITY_PUBLIC
                )
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(
                    openPendingIntent
                )
                .addAction(
                    android.R.drawable
                        .ic_menu_close_clear_cancel,
                    "Decline",
                    rejectPendingIntent
                )
                .addAction(
                    android.R.drawable
                        .sym_action_call,
                    "Accept",
                    acceptPendingIntent
                )

        applyFullScreenIntentIfAllowed(
            builder = builder,
            pendingIntent = openPendingIntent
        )

        val notification =
            builder.build()

        return postNotification(
            id = INCOMING_NOTIFICATION_ID,
            notification = notification
        )
    }

    @SuppressLint("FullScreenIntentPolicy")
    private fun applyFullScreenIntentIfAllowed(
        builder: NotificationCompat.Builder,
        pendingIntent: PendingIntent
    ) {
        if (!canUseFullScreenIntent()) {
            return
        }

        builder.setFullScreenIntent(
            pendingIntent,
            true
        )
    }

    private fun showActiveCallNotification(
        callId: String,
        title: String,
        body: String
    ): Boolean {

        if (!canPostNotifications()) {
            return false
        }

        val openIntent =
            createCallIntent(
                callId = callId,
                action = ACTION_OPEN
            )

        val openPendingIntent =
            PendingIntent.getActivity(
                this,
                requestCode(
                    callId = callId,
                    suffix = 4
                ),
                openIntent,
                pendingIntentFlags()
            )

        val notification =
            NotificationCompat.Builder(
                this,
                ACTIVE_CHANNEL_ID
            )
                .setSmallIcon(
                    applicationInfo.icon
                )
                .setContentTitle(title)
                .setContentText(body)
                .setCategory(
                    NotificationCompat.CATEGORY_CALL
                )
                .setPriority(
                    NotificationCompat.PRIORITY_HIGH
                )
                .setVisibility(
                    NotificationCompat.VISIBILITY_PRIVATE
                )
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(
                    openPendingIntent
                )
                .build()

        return postNotification(
            id = ACTIVE_NOTIFICATION_ID,
            notification = notification
        )
    }

    @SuppressLint("MissingPermission")
    private fun postNotification(
        id: Int,
        notification: Notification
    ): Boolean {

        if (!canPostNotifications()) {
            return false
        }

        return try {
            NotificationManagerCompat
                .from(this)
                .notify(
                    id,
                    notification
                )

            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun canPostNotifications(): Boolean {

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.TIRAMISU
        ) {
            val granted =
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) ==
                        PackageManager.PERMISSION_GRANTED

            if (!granted) {
                return false
            }
        }

        return NotificationManagerCompat
            .from(this)
            .areNotificationsEnabled()
    }

    private fun canUseFullScreenIntent(): Boolean {

        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.Q
        ) {
            return true
        }

        val manifestPermissionGranted =
            ContextCompat.checkSelfPermission(
                this,
                PERMISSION_USE_FULL_SCREEN_INTENT
            ) ==
                    PackageManager.PERMISSION_GRANTED

        if (!manifestPermissionGranted) {
            return false
        }

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        ) {
            val manager =
                getSystemService(
                    NotificationManager::class.java
                )

            return manager.canUseFullScreenIntent()
        }

        return true
    }

    private fun createNotificationChannels() {

        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }

        val manager =
            getSystemService(
                NotificationManager::class.java
            )

        createIncomingNotificationChannel(
            manager
        )

        createActiveNotificationChannel(
            manager
        )
    }

    private fun createIncomingNotificationChannel(
        manager: NotificationManager
    ) {
        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }

        val ringtone =
            RingtoneManager.getDefaultUri(
                RingtoneManager.TYPE_RINGTONE
            )

        val audioAttributes =
            AudioAttributes.Builder()
                .setUsage(
                    AudioAttributes
                        .USAGE_NOTIFICATION_RINGTONE
                )
                .build()

        val channel =
            NotificationChannel(
                INCOMING_CHANNEL_ID,
                INCOMING_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {

                description =
                    "Incoming JR CALL voice and video calls"

                enableVibration(true)

                lockscreenVisibility =
                    Notification.VISIBILITY_PUBLIC

                setSound(
                    ringtone,
                    audioAttributes
                )
            }

        manager.createNotificationChannel(
            channel
        )
    }

    private fun createActiveNotificationChannel(
        manager: NotificationManager
    ) {
        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }

        val channel =
            NotificationChannel(
                ACTIVE_CHANNEL_ID,
                ACTIVE_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {

                description =
                    "Active JR CALL voice and video calls"

                enableVibration(false)

                setSound(
                    null,
                    null
                )

                lockscreenVisibility =
                    Notification.VISIBILITY_PRIVATE
            }

        manager.createNotificationChannel(
            channel
        )
    }

    private fun createCallIntent(
        callId: String,
        action: String
    ): Intent {

        return Intent(
            this,
            MainActivity::class.java
        ).apply {

            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP

            putExtra(
                EXTRA_CALL_ID,
                callId
            )

            putExtra(
                EXTRA_CALL_ACTION,
                action
            )
        }
    }

    private fun handleLaunchIntent(
        launchIntent: Intent?
    ) {
        if (
            launchIntent == null ||
            !flutterEngineReady
        ) {
            return
        }

        val callId =
            readString(
                launchIntent.getStringExtra(
                    EXTRA_CALL_ID
                )
            ) ?: return

        val action =
            readString(
                launchIntent.getStringExtra(
                    EXTRA_CALL_ACTION
                )
            ) ?: ACTION_OPEN

        val deliveryKey =
            "$callId|$action"

        if (
            lastDeliveredActionKey ==
            deliveryKey
        ) {
            clearHandledIntent(
                launchIntent
            )

            return
        }

        lastDeliveredActionKey =
            deliveryKey

        val storedPayload =
            loadPendingCall()

        val payload =
            storedPayload.ifEmpty {
                mapOf<String, Any?>(
                    "callId" to callId
                )
            }

        window.decorView.post {

            when (action) {

                ACTION_ACCEPT -> {
                    methodChannel?.invokeMethod(
                        "incomingCallAccepted",
                        mapOf<String, Any?>(
                            "callId" to callId
                        )
                    )
                }

                ACTION_REJECT -> {
                    methodChannel?.invokeMethod(
                        "incomingCallRejected",
                        mapOf<String, Any?>(
                            "callId" to callId
                        )
                    )
                }

                else -> {
                    methodChannel?.invokeMethod(
                        "appLaunchedForCall",
                        payload
                    )
                }
            }

            clearHandledIntent(
                launchIntent
            )
        }
    }

    private fun clearHandledIntent(
        handledIntent: Intent
    ) {
        handledIntent.removeExtra(
            EXTRA_CALL_ID
        )

        handledIntent.removeExtra(
            EXTRA_CALL_ACTION
        )
    }

    private fun preferences():
            SharedPreferences {

        return getSharedPreferences(
            PREFS_NAME,
            MODE_PRIVATE
        )
    }

    @SuppressLint("UseKtx")
    private fun savePendingCall(
        payload: Map<String, Any?>
    ) {
        val json =
            mapToJson(payload)

        val editor =
            preferences().edit()

        editor.putString(
            PREF_PENDING_CALL,
            json.toString()
        )

        editor.apply()
    }

    private fun loadPendingCall():
            Map<String, Any?> {

        val raw =
            preferences()
                .getString(
                    PREF_PENDING_CALL,
                    null
                )
                ?: return emptyMap()

        return try {
            jsonToMap(
                JSONObject(raw)
            )
        } catch (_: Throwable) {
            emptyMap()
        }
    }

    @SuppressLint("UseKtx")
    private fun clearPendingCall() {

        val editor =
            preferences().edit()

        editor.remove(
            PREF_PENDING_CALL
        )

        editor.apply()
    }

    private fun mapToJson(
        map: Map<String, Any?>
    ): JSONObject {

        val json =
            JSONObject()

        for (
        (key, value) in map
        ) {
            json.put(
                key,
                toJsonValue(value)
            )
        }

        return json
    }

    private fun toJsonValue(
        value: Any?
    ): Any? {

        return when (value) {

            null ->
                JSONObject.NULL

            is JSONObject ->
                value

            is JSONArray ->
                value

            is String ->
                value

            is Number ->
                value

            is Boolean ->
                value

            is Map<*, *> -> {
                val normalized =
                    mutableMapOf<String, Any?>()

                for (
                (key, nestedValue) in value
                ) {
                    key
                        ?.toString()
                        ?.let { normalizedKey ->
                            normalized[
                                normalizedKey
                            ] = nestedValue
                        }
                }

                mapToJson(
                    normalized
                )
            }

            is Iterable<*> -> {
                val array =
                    JSONArray()

                for (
                entry in value
                ) {
                    array.put(
                        toJsonValue(
                            entry
                        )
                    )
                }

                array
            }

            is Array<*> -> {
                val array =
                    JSONArray()

                for (
                entry in value
                ) {
                    array.put(
                        toJsonValue(
                            entry
                        )
                    )
                }

                array
            }

            else ->
                value.toString()
        }
    }

    private fun jsonToMap(
        json: JSONObject
    ): Map<String, Any?> {

        val result =
            mutableMapOf<String, Any?>()

        val keys =
            json.keys()

        while (
            keys.hasNext()
        ) {
            val key =
                keys.next()

            result[key] =
                fromJsonValue(
                    json.opt(key)
                )
        }

        return result
    }

    private fun fromJsonValue(
        value: Any?
    ): Any? {

        return when (value) {

            null ->
                null

            JSONObject.NULL ->
                null

            is JSONObject ->
                jsonToMap(value)

            is JSONArray -> {
                val result =
                    mutableListOf<Any?>()

                for (
                index in
                0 until value.length()
                ) {
                    result.add(
                        fromJsonValue(
                            value.opt(index)
                        )
                    )
                }

                result
            }

            else ->
                value
        }
    }

    private fun cancelIncomingNotification() {
        NotificationManagerCompat
            .from(this)
            .cancel(
                INCOMING_NOTIFICATION_ID
            )
    }

    private fun cancelActiveNotification() {
        NotificationManagerCompat
            .from(this)
            .cancel(
                ACTIVE_NOTIFICATION_ID
            )
    }

    private fun normalizeArguments(
        arguments: Any?
    ): Map<String, Any?> {

        if (
            arguments !is Map<*, *>
        ) {
            return emptyMap()
        }

        val normalized =
            mutableMapOf<String, Any?>()

        for (
        (key, value) in arguments
        ) {
            key
                ?.toString()
                ?.let { normalizedKey ->
                    normalized[
                        normalizedKey
                    ] = value
                }
        }

        return normalized
    }

    private fun readString(
        value: Any?
    ): String? {

        val normalized =
            value
                ?.toString()
                ?.trim()
                ?: return null

        return normalized
            .ifEmpty {
                null
            }
    }

    private fun readBoolean(
        value: Any?
    ): Boolean {

        return when (value) {

            is Boolean ->
                value

            is Number ->
                value.toInt() != 0

            is String -> {
                when (
                    value
                        .trim()
                        .lowercase()
                ) {
                    "true",
                    "1",
                    "yes",
                    "video" ->
                        true

                    else ->
                        false
                }
            }

            else ->
                false
        }
    }

    private fun requestCode(
        callId: String,
        suffix: Int
    ): Int {

        return (
                31 *
                        callId.hashCode()
                ) + suffix
    }

    private fun pendingIntentFlags():
            Int {

        return PendingIntent
            .FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
    }

    override fun cleanUpFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        flutterEngineReady = false

        methodChannel
            ?.setMethodCallHandler(
                null
            )

        methodChannel = null

        lastDeliveredActionKey = null

        super.cleanUpFlutterEngine(
            flutterEngine
        )
    }
}

// ===============================================================
// END OF FILE
// ===============================================================