package com.easysubway.play_integrity_channel

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PlayIntegrityMethodChannelPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var handler: Handler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handler = Handler(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, channelName).also { channel ->
            channel.setMethodCallHandler(handler)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handler?.detach()
        handler = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private class Handler(private val context: Context) : MethodChannel.MethodCallHandler {
        private var pending: MethodChannel.Result? = null
        private var provider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
        private var projectNumber: Long? = null
        private var detached = false

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            if (detached) {
                result.error("integrityUnavailable", "Play Integrity engine is detached", null)
                return
            }
            if (call.method != "requestToken") return result.notImplemented()
            val hash = call.argument<String>("requestHash")
            val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
            if (pending != null || hash == null || !hash.matches(requestHashPattern) || project == null || project <= 0) {
                result.error("integrityUnavailable", "invalid integrity request", null)
                return
            }
            pending = result
            val cached = provider
            if (cached != null && projectNumber == project) return request(cached, hash)
            IntegrityManagerFactory.createStandard(context).prepareIntegrityToken(
                StandardIntegrityManager.PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build(),
            ).addOnSuccessListener { prepared ->
                if (detached) return@addOnSuccessListener
                provider = prepared
                projectNumber = project
                request(prepared, hash)
            }.addOnFailureListener { if (!detached) fail() }
        }

        private fun request(provider: StandardIntegrityManager.StandardIntegrityTokenProvider, hash: String) {
            provider.request(StandardIntegrityManager.StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                .addOnSuccessListener { response ->
                    if (!detached) {
                        pending?.success(response.token())
                        pending = null
                    }
                }.addOnFailureListener {
                    if (!detached) {
                        provider = null
                        projectNumber = null
                        fail()
                    }
                }
        }

        private fun fail() {
            pending?.error("integrityUnavailable", "Play Integrity token is unavailable", null)
            pending = null
        }

        fun detach() {
            detached = true
            pending?.error("integrityUnavailable", "Play Integrity engine is detached", null)
            pending = null
            provider = null
            projectNumber = null
        }
    }

    private companion object {
        const val channelName = "com.easysubway.easysubway_mobile/play_integrity"
        val requestHashPattern = Regex("^[A-Za-z0-9_-]{43}$")
    }
}
