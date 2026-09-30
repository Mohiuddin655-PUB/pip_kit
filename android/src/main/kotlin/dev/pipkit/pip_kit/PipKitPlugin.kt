package dev.pipkit.pip_kit

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Android Picture in Picture for the whole Flutter Activity.
 *
 * Android has no notion of putting one view in the window: the Activity itself
 * shrinks into it. So this side only manages the window — its shape, automatic
 * entry, the action buttons — and reports when it opens and closes. What is
 * drawn inside is decided in Dart by `PipHost`.
 */
class PipKitPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null

    private var params: PictureInPictureParams? = null
    private var autoEnter = false
    private var isOpen = false

    private var configurationCallbacks: ComponentCallbacks? = null
    private var userLeaveHintListener: PluginRegistry.UserLeaveHintListener? = null
    private var actionReceiver: BroadcastReceiver? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pip_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "configure" -> result.success(configure(call))
            "enter" -> result.success(enter())
            "exit" -> result.success(exit())
            "release" -> {
                release()
                result.success(true)
            }
            // Frames are an iOS concept; here the Activity draws itself.
            "pushFrame" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Window
    // -------------------------------------------------------------------------

    private fun isSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val context = activity ?: return false
        return context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun configure(call: MethodCall): Boolean {
        val currentActivity = activity ?: return false
        if (!isSupported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false

        autoEnter = call.argument<Boolean>("autoEnter") ?: false
        val ratioWidth = call.argument<Int>("aspectRatioWidth") ?: 9
        val ratioHeight = call.argument<Int>("aspectRatioHeight") ?: 16
        val actions = call.argument<List<Map<String, Any?>>>("actions") ?: emptyList()

        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(clampAspectRatio(ratioWidth, ratioHeight))
            .setActions(buildActions(currentActivity, actions))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(call.argument<Boolean>("seamlessResize") ?: true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            call.argument<String>("title")?.let(builder::setTitle)
            call.argument<String>("subtitle")?.let(builder::setSubtitle)
        }

        return try {
            val built = builder.build()
            params = built
            currentActivity.setPictureInPictureParams(built)
            true
        } catch (error: Exception) {
            // Thrown when the Activity does not declare
            // android:supportsPictureInPicture="true".
            Log.e(TAG, "Could not apply Picture-in-Picture params", error)
            false
        }
    }

    /** Android refuses anything outside 1:2.39 … 2.39:1. */
    private fun clampAspectRatio(width: Int, height: Int): Rational {
        if (width <= 0 || height <= 0) return Rational(9, 16)
        val ratio = width.toDouble() / height.toDouble()
        return when {
            ratio < 1 / 2.39 -> Rational(100, 239)
            ratio > 2.39 -> Rational(239, 100)
            else -> Rational(width, height)
        }
    }

    private fun enter(): Boolean {
        val currentActivity = activity ?: return false
        if (!isSupported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (currentActivity.isInPictureInPictureMode) return true
        return try {
            currentActivity.enterPictureInPictureMode(
                params ?: PictureInPictureParams.Builder().build()
            )
        } catch (error: Exception) {
            Log.e(TAG, "Could not enter Picture in Picture", error)
            false
        }
    }

    /**
     * An app cannot dismiss its own window; the closest it can do is bring the
     * task back to full screen, which ends Picture in Picture.
     */
    private fun exit(): Boolean {
        val currentActivity = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!currentActivity.isInPictureInPictureMode) return false
        return try {
            val intent = Intent(currentActivity, currentActivity.javaClass)
                .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            currentActivity.startActivity(intent)
            true
        } catch (error: Exception) {
            Log.e(TAG, "Could not leave Picture in Picture", error)
            false
        }
    }

    private fun release() {
        autoEnter = false
        val currentActivity = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val builder = PictureInPictureParams.Builder().setActions(emptyList())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(false)
            }
            val built = builder.build()
            params = null
            currentActivity.setPictureInPictureParams(built)
        } catch (error: Exception) {
            Log.e(TAG, "Could not clear Picture-in-Picture params", error)
        }
    }

    // -------------------------------------------------------------------------
    // Actions
    // -------------------------------------------------------------------------

    private fun buildActions(
        context: Activity,
        actions: List<Map<String, Any?>>
    ): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        return actions.take(context.maxNumPictureInPictureActions).mapIndexedNotNull { index, raw ->
            val id = raw["id"] as? String ?: return@mapIndexedNotNull null
            val label = raw["label"] as? String ?: id
            val iconRes = resolveIcon(context, raw["icon"] as? String)
            val intent = Intent(actionName(context))
                .setPackage(context.packageName)
                .putExtra(EXTRA_ACTION_ID, id)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                // Distinct request codes keep the extras of each button apart.
                REQUEST_CODE_BASE + index,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            RemoteAction(
                Icon.createWithResource(context, iconRes),
                label,
                label,
                pendingIntent
            ).apply { isEnabled = raw["enabled"] as? Boolean ?: true }
        }
    }

    private fun resolveIcon(context: Context, name: String?): Int {
        if (name != null && name.startsWith("res:")) {
            val resource = context.resources.getIdentifier(
                name.removePrefix("res:"),
                "drawable",
                context.packageName
            )
            if (resource != 0) return resource
            Log.w(TAG, "No drawable named ${name.removePrefix("res:")}; using a default icon")
        }
        return when (name) {
            "play" -> android.R.drawable.ic_media_play
            "pause" -> android.R.drawable.ic_media_pause
            "next" -> android.R.drawable.ic_media_next
            "previous" -> android.R.drawable.ic_media_previous
            "rewind" -> android.R.drawable.ic_media_rew
            "fastForward" -> android.R.drawable.ic_media_ff
            "close" -> android.R.drawable.ic_menu_close_clear_cancel
            "add" -> android.R.drawable.ic_input_add
            "delete" -> android.R.drawable.ic_menu_delete
            "info" -> android.R.drawable.ic_menu_info_details
            "share" -> android.R.drawable.ic_menu_share
            "send" -> android.R.drawable.ic_menu_send
            else -> android.R.drawable.ic_menu_info_details
        }
    }

    private fun actionName(context: Context) = "${context.packageName}.PIP_KIT_ACTION"

    private fun registerActionReceiver(context: Activity) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                val id = intent.getStringExtra(EXTRA_ACTION_ID) ?: return
                mainHandler.post { channel.invokeMethod("onAction", id) }
            }
        }
        val filter = IntentFilter(actionName(context))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        actionReceiver = receiver
    }

    // -------------------------------------------------------------------------
    // Status
    // -------------------------------------------------------------------------

    /**
     * The embedding does not forward `onPictureInPictureModeChanged` to
     * plugins, but entering and leaving the window always changes the
     * Activity's configuration, so that is what is watched.
     */
    private fun watchStatus(context: Activity) {
        val callbacks = object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) = syncStatus()
            override fun onLowMemory() {}
        }
        context.registerComponentCallbacks(callbacks)
        configurationCallbacks = callbacks
    }

    private fun syncStatus() {
        val nowOpen = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity?.isInPictureInPictureMode == true
        if (nowOpen == isOpen) return
        isOpen = nowOpen
        channel.invokeMethod("onStatus", nowOpen)
    }

    /**
     * Android 11 and below have no `setAutoEnterEnabled`, so the window has to
     * be opened as the user leaves. On 12+ the system has already done it.
     */
    private fun watchUserLeaving(pluginBinding: ActivityPluginBinding) {
        val listener = PluginRegistry.UserLeaveHintListener {
            if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
        }
        pluginBinding.addOnUserLeaveHintListener(listener)
        userLeaveHintListener = listener
    }

    // -------------------------------------------------------------------------
    // Activity
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        attach(binding)

    override fun onDetachedFromActivityForConfigChanges() = detach()

    override fun onDetachedFromActivity() = detach()

    private fun attach(pluginBinding: ActivityPluginBinding) {
        binding = pluginBinding
        activity = pluginBinding.activity
        watchStatus(pluginBinding.activity)
        watchUserLeaving(pluginBinding)
        registerActionReceiver(pluginBinding.activity)
        syncStatus()
    }

    private fun detach() {
        val currentActivity = activity
        configurationCallbacks?.let { currentActivity?.unregisterComponentCallbacks(it) }
        configurationCallbacks = null
        userLeaveHintListener?.let { binding?.removeOnUserLeaveHintListener(it) }
        userLeaveHintListener = null
        actionReceiver?.let {
            try {
                currentActivity?.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered with the Activity.
            }
        }
        actionReceiver = null
        binding = null
        activity = null
    }

    private companion object {
        const val TAG = "PipKit"
        const val EXTRA_ACTION_ID = "pip_kit_action_id"
        const val REQUEST_CODE_BASE = 0x5049
    }
}
