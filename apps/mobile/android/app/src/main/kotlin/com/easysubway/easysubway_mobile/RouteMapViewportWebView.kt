package com.easysubway.easysubway_mobile

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.IOException
import org.json.JSONObject

private val routeMapFontAssets = listOf(
    400 to "fonts/Pretendard-Regular.otf",
    600 to "fonts/Pretendard-SemiBold.otf",
    700 to "fonts/Pretendard-Bold.otf",
    800 to "fonts/Pretendard-ExtraBold.otf",
    900 to "fonts/Pretendard-Black.otf",
)

// ponytail: local fonts get 5s; add a JS bridge only if cold-load evidence exceeds this bound.
private const val fontReadinessMaxAttempts = 100
private const val fontReadinessPollMillis = 16L

class RouteMapViewportWebViewFactory(
    codec: StandardMessageCodec,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(codec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        return RouteMapViewportPlatformView(
            context = context,
            messenger = messenger,
            viewId = viewId,
            assetPath = params["assetPath"] as? String ?: "",
            mimeType = params["mimeType"] as? String ?: "",
            viewBox = params["viewBox"].asDoubleList(),
            revision = params["revision"].asInt(),
            frameToken = params["frameToken"].asInt(),
        )
    }
}

private class RouteMapViewportPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val assetPath: String,
    private val mimeType: String,
    private var viewBox: List<Double>,
    private var revision: Int,
    private var frameToken: Int,
) : PlatformView {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isDebuggable =
        context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private val container = FrameLayout(context).apply {
        isClickable = false
        isFocusable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
    }
    private val channel = MethodChannel(
        messenger,
        "com.easysubway.easysubway_mobile/route_map_viewport_webview/$viewId",
    )
    private var webView: WebView? = null
    @Volatile
    private var initialAssetUrl: String? = null
    @Volatile
    private var fontUrls = emptySet<String>()
    private var documentReady = false
    private var fontReadinessAttempts = 0
    private var isDisposed = false
    private var started = false

    init {
        Log.d("RouteMapViewport", "init viewId=$viewId viewBox=$viewBox revision=$revision")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    Log.d("RouteMapViewport", "method start started=$started")
                    if (!started) {
                        started = true
                        load()
                    }
                    result.success(null)
                }
                "setCamera" -> {
                    viewBox = call.argument<Any>("viewBox").asDoubleList()
                    revision = call.argument<Any>("revision").asInt()
                    frameToken = call.argument<Any>("frameToken").asInt()
                    Log.d("RouteMapViewport", "method setCamera viewBox=$viewBox revision=$revision frameToken=$frameToken docReady=$documentReady")
                    if (documentReady) applyViewBox()
                    result.success(null)
                }
                "loadAsset" -> {
                    val newAssetPath = call.argument<String>("assetPath") ?: ""
                    viewBox = call.argument<Any>("viewBox").asDoubleList()
                    revision = call.argument<Any>("revision").asInt()
                    frameToken = call.argument<Any>("frameToken").asInt()
                    Log.d("RouteMapViewport", "method loadAsset path=$newAssetPath viewBox=$viewBox revision=$revision frameToken=$frameToken")
                    load(newAssetPath)
                    result.success(null)
                }
                "reload" -> {
                    load()
                    result.success(null)
                }
                "trimMemory" -> {
                    webView?.clearCache(false)
                    result.success(null)
                }
                "debugFault" -> handleDebugFault(call.argument<String>("kind"), result)
                "dispose" -> {
                    Log.d("RouteMapViewport", "method dispose viewId=$viewId")
                    dispose()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private inner class EasySubwayJsBridge {
        @JavascriptInterface
        fun onFontsReady() {
            mainHandler.post {
                if (!isDisposed && !documentReady) {
                    Log.d("RouteMapViewport", "EasySubwayJsBridge.onFontsReady")
                    documentReady = true
                    applyViewBox()
                }
            }
        }

        @JavascriptInterface
        fun onFontsFailed() {
            mainHandler.post {
                if (!isDisposed && !documentReady) {
                    Log.w("RouteMapViewport", "EasySubwayJsBridge.onFontsFailed, proceeding with system fonts")
                    documentReady = true
                    applyViewBox()
                }
            }
        }
    }

    private fun load(assetPathOverride: String? = null) {
        if (isDisposed) return
        documentReady = false
        fontReadinessAttempts = 0
        fontUrls = emptySet()
        val path = assetPathOverride ?: assetPath
        val resolvedUrl = resolvedAssetUrl(path)
        val resolvedFonts = resolvedFontUrls()
        Log.d("RouteMapViewport", "load url=$resolvedUrl fonts=${resolvedFonts?.size}")
        if (resolvedUrl == null || resolvedFonts == null) {
            reportAssetLoadFailed("resolvedUrl or resolvedFonts is null: path=$path")
            return
        }
        initialAssetUrl = resolvedUrl
        fontUrls = resolvedFonts.values.toSet()
        val current = webView
        if (current != null) {
            current.loadUrl(resolvedUrl)
            return
        }
        destroyWebView()
        container.removeAllViews()
        var svgWebView: WebView? = null
        try {
            val candidate = WebView(container.context).apply {
                isClickable = false
                isFocusable = false
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                setOnTouchListener { _, _ -> true }
                isHorizontalScrollBarEnabled = false
                isVerticalScrollBarEnabled = false
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                setLayerType(View.LAYER_TYPE_HARDWARE, null)
                settings.javaScriptEnabled = true
                settings.javaScriptCanOpenWindowsAutomatically = false
                settings.builtInZoomControls = false
                settings.displayZoomControls = false
                settings.useWideViewPort = false
                settings.loadWithOverviewMode = false
                settings.textZoom = 100
                settings.blockNetworkLoads = true
                settings.allowContentAccess = false
                settings.allowFileAccess = true
                webViewClient = routeMapWebViewClient()
                addJavascriptInterface(EasySubwayJsBridge(), "easySubwayBridge")
            }
            svgWebView = candidate
            webView = candidate
            container.addView(candidate, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ))
            candidate.loadUrl(resolvedUrl)
        } catch (_: RuntimeException) {
            webView = null
            svgWebView?.let { candidate ->
                runCatching { container.removeView(candidate) }
                runCatching { candidate.destroy() }
            }
            reportAssetLoadFailed()
        }
    }

    private fun resolvedAssetUrl(path: String): String? {
        if (mimeType != "image/svg+xml" || path.isBlank()) return null
        return try {
            val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
            container.context.assets.open(lookupKey).close()
            "file:///android_asset/$lookupKey"
        } catch (_: IOException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun resolvedFontUrls(): Map<Int, String>? {
        return try {
            routeMapFontAssets.associate { (weight, path) ->
                val lookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
                container.context.assets.open(lookupKey).close()
                weight to "file:///android_asset/$lookupKey"
            }
        } catch (_: IOException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun routeMapWebViewClient(): WebViewClient =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Api26RouteMapWebViewClient()
        } else {
            RouteMapWebViewClient()
        }

    private open inner class RouteMapWebViewClient : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val allowed = request.url.toString() == initialAssetUrl
            if (!allowed && request.isForMainFrame && !isDisposed && webView === view) {
                reportAssetLoadFailed("shouldOverrideUrlLoading mainFrame disallowed: ${request.url}")
            }
            return !allowed
        }

        @Deprecated("Old Android callback kept so external navigation stays blocked.")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
            val allowed = url == initialAssetUrl
            if (!allowed && !isDisposed && webView === view) {
                reportAssetLoadFailed("shouldOverrideUrlLoading disallowed: $url")
            }
            return !allowed
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            val url = request.url.toString()
            if (url == initialAssetUrl || url in fontUrls) return null
            return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
        }

        override fun onPageFinished(view: WebView, url: String) {
            Log.d("RouteMapViewport", "onPageFinished url=$url webViewMatches=${webView === view} isDisposed=$isDisposed")
            if (isDisposed || webView !== view || url != initialAssetUrl) {
                return
            }
            prepareDocument(view)
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            Log.w("RouteMapViewport", "onReceivedError error=${error.description} mainFrame=${request.isForMainFrame}")
            if (!isDisposed && webView === view && request.isForMainFrame) {
                reportAssetLoadFailed("onReceivedError: ${error.description}")
            }
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.O)
    private inner class Api26RouteMapWebViewClient : RouteMapWebViewClient() {
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            Log.e("RouteMapViewport", "onRenderProcessGone didCrash=${detail.didCrash()}")
            handleProcessGone(view, detail.didCrash())
            return true
        }
    }

    private fun prepareDocument(currentWebView: WebView) {
        val fonts = resolvedFontUrls() ?: run {
            reportAssetLoadFailed("prepareDocument resolvedFontUrls is null")
            return
        }
        val css = fonts.entries.joinToString("") { (weight, url) ->
            "@font-face{font-family:'Pretendard';src:url('$url') format('opentype');" +
                "font-weight:$weight;font-style:normal;font-display:block;}"
        } + "html, body, svg { background: transparent !important; background-color: transparent !important; margin: 0; padding: 0; overflow: hidden; }" +
            "svg{text-rendering:geometricPrecision;shape-rendering:geometricPrecision;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;}"
        // The asset stays byte-identical; this only resolves its declared Pretendard family.
        val script = """
            (function(){
              const svg=document.documentElement;
              if(!svg||svg.tagName.toLowerCase()!=='svg'||!document.fonts){return false;}
              const style=document.createElementNS('http://www.w3.org/2000/svg','style');
              style.textContent=${JSONObject.quote(css)};
              svg.insertBefore(style,svg.firstChild);
              const allowed=['viewBox','width','height','preserveAspectRatio'];
              window.__easySubwaySvgIntegrityViolation=false;
              const observer=new MutationObserver((records)=>{
                for(const record of records){
                  if(record.target!==svg){continue;}
                  if(record.type==='attributes'&&allowed.includes(record.attributeName)){continue;}
                  window.__easySubwaySvgIntegrityViolation=true;
                  observer.disconnect();
                  break;
                }
              });
              observer.observe(svg,{subtree:true,childList:true,characterData:true,attributes:true});
              window.__easySubwaySvgObserver=observer;
              window.__easySubwayFontState='pending';
              const specs=['400 12px Pretendard','600 12px Pretendard','700 12px Pretendard','800 12px Pretendard','900 12px Pretendard'];
              Promise.all(specs.map((spec)=>document.fonts.load(spec,'가'))).then(()=>{
                const ready=specs.every((spec)=>document.fonts.check(spec,'가'));
                window.__easySubwayFontState=ready?'ready':'failed';
                if(window.easySubwayBridge){
                  if(ready){window.easySubwayBridge.onFontsReady();}
                  else{window.easySubwayBridge.onFontsFailed();}
                }
              }).catch(()=>{
                window.__easySubwayFontState='failed';
                if(window.easySubwayBridge){window.easySubwayBridge.onFontsFailed();}
              });
              return true;
            })();
        """.trimIndent()
        currentWebView.evaluateJavascript(script) { result ->
            Log.d("RouteMapViewport", "prepareDocument script result=$result isDisposed=$isDisposed webViewMatches=${webView === currentWebView}")
            if (isDisposed || webView !== currentWebView) return@evaluateJavascript
            if (result != "true") {
                reportAssetLoadFailed("prepareDocument evaluateJavascript returned $result")
                return@evaluateJavascript
            }
            documentReady = true
            applyViewBox()
            pollDocumentReady(currentWebView)
        }
    }

    private fun pollDocumentReady(currentWebView: WebView) {
        if (isDisposed || webView !== currentWebView || documentReady) return
        currentWebView.evaluateJavascript("window.__easySubwayFontState || 'failed'") { result ->
            Log.d("RouteMapViewport", "pollDocumentReady result=$result attempts=$fontReadinessAttempts")
            if (isDisposed || webView !== currentWebView || documentReady) return@evaluateJavascript
            when (result) {
                "\"ready\"" -> {
                    documentReady = true
                    applyViewBox()
                }
                "\"failed\"" -> {
                    Log.w("RouteMapViewport", "pollDocumentReady fonts reported failed, proceeding with system fonts")
                    documentReady = true
                    applyViewBox()
                }
                else -> {
                    fontReadinessAttempts += 1
                    if (fontReadinessAttempts >= fontReadinessMaxAttempts) {
                        Log.w("RouteMapViewport", "pollDocumentReady max attempts reached, proceeding with system fonts")
                        documentReady = true
                        applyViewBox()
                    } else {
                        mainHandler.postDelayed(
                            { pollDocumentReady(currentWebView) },
                            fontReadinessPollMillis,
                        )
                    }
                }
            }
        }
    }

    private fun applyViewBox() {
        val currentWebView = webView ?: run {
            if (!isDisposed) reportCameraApplyFailed("webView is null")
            return
        }
        val values = viewBox
        if (values.isEmpty()) {
            Log.d("RouteMapViewport", "applyViewBox: viewBox is empty, waiting for camera")
            return
        }
        if (!isValidViewBox(values)) {
            Log.e("RouteMapViewport", "applyViewBox: viewBox is invalid: $values")
            if (!isDisposed) reportCameraApplyFailed("viewBox is invalid: $values")
            return
        }
        val frameRevision = revision
        val presentedFrameToken = frameToken
        val encodedValues = values.joinToString(",") { value -> value.toString() }
        val script = """
            (function(){
              const values=[$encodedValues];
              const svg=document.documentElement;
              if(!svg||svg.tagName.toLowerCase()!=='svg'||window.__easySubwaySvgIntegrityViolation===true||values.length!==4||!values.every(Number.isFinite)||values[2]<=0||values[3]<=0){return false;}
              svg.setAttribute('viewBox',values.join(' '));
              svg.setAttribute('width','100%');
              svg.setAttribute('height','100%');
              svg.setAttribute('preserveAspectRatio','xMidYMid meet');
              return true;
            })();
        """.trimIndent()
        Log.d("RouteMapViewport", "applyViewBox evaluating script with viewBox=$encodedValues revision=$frameRevision token=$presentedFrameToken")
        currentWebView.evaluateJavascript(script) { result ->
            Log.d("RouteMapViewport", "applyViewBox script result=$result isDisposed=$isDisposed webViewMatches=${webView === currentWebView}")
            if (isDisposed || webView !== currentWebView) {
                return@evaluateJavascript
            }
            if (result != "true") {
                reportCameraApplyFailed("applyViewBox script failed: result=$result")
            } else {
                currentWebView.postVisualStateCallback(
                    frameRevision.toLong(),
                    object : WebView.VisualStateCallback() {
                        override fun onComplete(requestId: Long) {
                            Log.d("RouteMapViewport", "postVisualStateCallback.onComplete requestId=$requestId frameRevision=$frameRevision token=$presentedFrameToken")
                            if (
                                !isDisposed &&
                                webView === currentWebView &&
                                requestId == frameRevision.toLong()
                            ) {
                                channel.invokeMethod(
                                    "framePresented",
                                    mapOf(
                                        "revision" to frameRevision,
                                        "frameToken" to presentedFrameToken,
                                    ),
                                )
                            }
                        }
                    },
                )
            }
        }
    }

    private fun isValidViewBox(values: List<Double>): Boolean =
        values.size == 4 && values.all { it.isFinite() } && values[2] > 0.0 && values[3] > 0.0

    private fun reportAssetLoadFailed(reason: String = "unspecified") {
        Log.e("RouteMapViewport", "reportAssetLoadFailed reason=$reason isDisposed=$isDisposed")
        if (isDisposed) return
        channel.invokeMethod("assetLoadFailed", null)
    }

    private fun reportAssetLoadFailedFromWebThread(reason: String = "unspecified") {
        if (isDisposed) return
        mainHandler.post { reportAssetLoadFailed(reason) }
    }

    private fun reportCameraApplyFailed(reason: String = "unspecified") {
        Log.e("RouteMapViewport", "reportCameraApplyFailed reason=$reason isDisposed=$isDisposed")
        if (isDisposed) return
        channel.invokeMethod("cameraApplyFailed", null)
    }

    private fun handleProcessGone(view: WebView?, didCrash: Boolean) {
        if (isDisposed || (view != null && webView !== view)) return
        channel.invokeMethod("processGone", mapOf("didCrash" to didCrash))
        webView?.let { current ->
            container.removeView(current)
            current.destroy()
        }
        webView = null
        documentReady = false
    }

    private fun handleDebugFault(kind: String?, result: MethodChannel.Result) {
        if (!isDebuggable) {
            result.error("debugUnavailable", "debug faults are unavailable in release", null)
            return
        }
        result.success(null)
        mainHandler.post {
            when (kind) {
                "invalidAsset" -> load("assets/datapacks/metro_map_pack/basemap/__missing_route_map__.svg")
                "invalidViewBox" -> {
                    viewBox = listOf(0.0, 0.0, Double.NaN, 1.0)
                    applyViewBox()
                }
                "debugProcessGone" -> handleProcessGone(webView, didCrash = true)
                else -> reportAssetLoadFailed()
            }
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        isDisposed = true
        mainHandler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
        destroyWebView()
        container.removeAllViews()
    }

    private fun destroyWebView() {
        webView?.let { view ->
            view.stopLoading()
            view.removeAllViews()
            view.destroy()
        }
        webView = null
        documentReady = false
    }
}

private fun Any?.asInt(): Int = when (this) {
    is Int -> this
    is Long -> toInt()
    is Double -> toInt()
    is Float -> toInt()
    else -> 0
}

private fun Any?.asDoubleList(): List<Double> {
    val values = this as? List<*> ?: return emptyList()
    return values.mapNotNull { value ->
        when (value) {
            is Double -> value
            is Float -> value.toDouble()
            is Int -> value.toDouble()
            is Long -> value.toDouble()
            else -> null
        }
    }
}
