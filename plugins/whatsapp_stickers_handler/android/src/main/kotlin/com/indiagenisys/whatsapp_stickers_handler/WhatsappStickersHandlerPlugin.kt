package com.indiagenisys.whatsapp_stickers_handler

import android.app.Activity
import android.content.*
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry

class WhatsappStickersHandlerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var result: MethodChannel.Result? = null
    private val addPackRequestCode = 200

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "whatsapp_stickers_handler")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        this.result = result
        when (call.method) {
            "platformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "isWhatsAppInstalled" -> result.success(WhitelistCheck.isWhatsAppInstalled(context!!))
            "isWhatsAppConsumerAppInstalled" -> result.success(WhitelistCheck.isWhatsAppConsumerAppInstalled(context?.packageManager))
            "isWhatsAppSmbAppInstalled" -> result.success(WhitelistCheck.isWhatsAppSmbAppInstalled(context?.packageManager))
            "isStickerPackInstalled" -> {
                val identifier = call.argument<String>("identifier") ?: return result.error("ARG_ERROR", "Missing identifier", null)
                result.success(WhitelistCheck.isWhitelisted(context!!, identifier))
            }
            "launchWhatsApp" -> {
                try {
                    val intent = context?.packageManager?.getLaunchIntentForPackage(WhitelistCheck.CONSUMER_WHATSAPP_PACKAGE_NAME)
                    activity?.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("LAUNCH_ERROR", "Failed to launch WhatsApp", e.message)
                }
            }
            "addStickerPack" -> {
                try {
                    val stickerPack: StickerPack = ConfigFileManager.fromMethodCall(context, call)
                    ConfigFileManager.addNewPack(context, stickerPack) // this updates content.json

                    context?.let { StickerPackValidator.verifyStickerPackValidity(it, stickerPack) }

                    val authority = getContentProviderAuthority(context!!)
                    val intent = createIntentToAddStickerPack(authority, stickerPack.identifier, stickerPack.name)
                    activity?.startActivityForResult(Intent.createChooser(intent, "Add Sticker"), addPackRequestCode)
                } catch (e: InvalidPackException) {
                    result.error(e.code, e.message, null)
                } catch (e: Exception) {
                    result.error("PACK_ERROR", e.message, null)
                }
            }
            "regenerateConfigFile" -> {
                try {
                    ConfigFileManager.generateConfigFile(context)
                    Log.d("StickerDebug", "🔁 Config file regenerated")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("StickerDebug", "❌ Failed to regenerate config file: ${e.message}")
                    result.error("CONFIG_ERROR", e.message, null)
                }
            }
            "getInstalledImageDataVersion" -> {
                val identifier = call.argument<String>("identifier")
                if (identifier == null) {
                    result.error("ARG_ERROR", "Missing identifier", null)
                    return
                }

                val packs = ConfigFileManager.getStickerPacks(context)
                val matchingPack = packs.firstOrNull { it.identifier == identifier }

                if (matchingPack != null) {
                    result.success(matchingPack.imageDataVersion?.toString())
                } else {
                    result.success(null) // Not installed
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == addPackRequestCode) {
            when (resultCode) {
                Activity.RESULT_OK -> {
                    val bundle = data?.extras
                    when {
                        bundle?.getBoolean("add_successful") == true -> result?.success("add_successful")
                        bundle?.getBoolean("already_added") == true -> result?.error("already_added", "Sticker pack already added", null)
                        else -> result?.success("success")
                    }
                }
                Activity.RESULT_CANCELED -> {
                    val error = data?.getStringExtra("validation_error")
                    result?.error("cancelled", error ?: "User cancelled", null)
                }
                else -> result?.success("unknown")
            }
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        context = binding.activity.applicationContext
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
        context = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun createIntentToAddStickerPack(authority: String, identifier: String?, name: String?): Intent {
        return Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK").apply {
            putExtra(EXTRA_STICKER_PACK_ID, identifier)
            putExtra(EXTRA_STICKER_PACK_AUTHORITY, authority)
            putExtra(EXTRA_STICKER_PACK_NAME, name)
        }
    }

    companion object {
        private const val EXTRA_STICKER_PACK_ID = "sticker_pack_id"
        private const val EXTRA_STICKER_PACK_AUTHORITY = "sticker_pack_authority"
        private const val EXTRA_STICKER_PACK_NAME = "sticker_pack_name"

        @JvmStatic
        fun getContentProviderAuthority(context: Context): String {
            return "${context.packageName}.stickercontentprovider"
        }

        @JvmStatic
        fun getContentProviderAuthorityURI(context: Context): Uri {
            return Uri.Builder()
                .scheme(ContentResolver.SCHEME_CONTENT)
                .authority(getContentProviderAuthority(context))
                .appendPath("metadata")
                .build()
        }
    }
}
