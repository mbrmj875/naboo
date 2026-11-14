package com.basra.storemanager.app

import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.core.graphics.Insets
import androidx.core.view.OnApplyWindowInsetsListener
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * adjustNothing + تصفير IME قبل FlutterView حتى لا يرسل المحرك
 * viewport metrics في كل إطار من حركة الكيبورد.
 *
 * ارتفاع IME يُبث عبر EventChannel. أثناء الإغلاق نُفضّل بثاً فورياً (و0)
 * حتى يعود الشريط السفلي بلا تأخير؛ أثناء الفتح نخفّض معدل البث لتقليل الجانك.
 */
class MainActivity : FlutterActivity() {
  private var imeStripInstalled = false
  private var imeEvents: EventChannel.EventSink? = null
  private var lastImeBottomPx = 0
  private var lastEmitUptimeMs = 0L

  private val imeStripper: OnApplyWindowInsetsListener =
    OnApplyWindowInsetsListener { view, insets ->
      emitImeBottom(insets.getInsets(WindowInsetsCompat.Type.ime()).bottom)
      val cleaned =
        WindowInsetsCompat.Builder(insets)
          .setInsets(WindowInsetsCompat.Type.ime(), Insets.NONE)
          .build()
      ViewCompat.setOnApplyWindowInsetsListener(view, null)
      val out: WindowInsetsCompat = ViewCompat.onApplyWindowInsets(view, cleaned)
      ViewCompat.setOnApplyWindowInsetsListener(view, imeStripper)
      out
    }

  private val imeAnimationCallback =
    object : WindowInsetsAnimationCompat.Callback(
      WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE,
    ) {
      override fun onProgress(
        insets: WindowInsetsCompat,
        runningAnimations: MutableList<WindowInsetsAnimationCompat>,
      ): WindowInsetsCompat {
        emitImeBottom(insets.getInsets(WindowInsetsCompat.Type.ime()).bottom)
        return insets
      }

      override fun onEnd(animation: WindowInsetsAnimationCompat) {
        if (animation.typeMask and WindowInsetsCompat.Type.ime() == 0) return
        // فرض المزامنة النهائية (0 عند الإغلاق) حتى لو تساوى الرقم مع آخر بث.
        forceEmitImeBottom(currentImeBottomPx())
      }
    }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    PinKdfChannel.register(flutterEngine)
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_IME_INSETS)
      .setStreamHandler(
        object : EventChannel.StreamHandler {
          override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            imeEvents = events
            events?.success(lastImeBottomPx)
          }

          override fun onCancel(arguments: Any?) {
            imeEvents = null
          }
        },
      )
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    applyFastImeMode()
  }

  override fun onResume() {
    super.onResume()
    applyFastImeMode()
    window.decorView.post {
      installImeInsetStripper()
      forceEmitImeBottom(currentImeBottomPx())
    }
  }

  private fun applyFastImeMode() {
    window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
  }

  private fun currentImeBottomPx(): Int {
    return ViewCompat.getRootWindowInsets(window.decorView)
      ?.getInsets(WindowInsetsCompat.Type.ime())
      ?.bottom
      ?: 0
  }

  private fun emitImeBottom(imeBottom: Int) {
    if (imeBottom == lastImeBottomPx) return
    val now = SystemClock.uptimeMillis()
    val closing = imeBottom < lastImeBottomPx
    val delta = kotlin.math.abs(imeBottom - lastImeBottomPx)
    // إغلاق أو وصول 0: فوري. فتح: كل ~32ms أو قفزة ≥24px لتقليل عاصفة الأحداث.
    if (imeBottom == 0 ||
      closing ||
      delta >= 24 ||
      now - lastEmitUptimeMs >= 32L
    ) {
      forceEmitImeBottom(imeBottom)
    }
  }

  private fun forceEmitImeBottom(imeBottom: Int) {
    lastImeBottomPx = imeBottom
    lastEmitUptimeMs = SystemClock.uptimeMillis()
    imeEvents?.success(imeBottom)
  }

  private fun installImeInsetStripper() {
    if (imeStripInstalled) return
    val flutterView = findFlutterView(window.decorView) ?: return
    ViewCompat.setWindowInsetsAnimationCallback(window.decorView, imeAnimationCallback)
    ViewCompat.setOnApplyWindowInsetsListener(flutterView, imeStripper)
    imeStripInstalled = true
    ViewCompat.requestApplyInsets(flutterView)
  }

  private fun findFlutterView(root: View): FlutterView? {
    if (root is FlutterView) return root
    if (root is ViewGroup) {
      for (i in 0 until root.childCount) {
        val found = findFlutterView(root.getChildAt(i))
        if (found != null) return found
      }
    }
    return null
  }

  companion object {
    private const val CHANNEL_IME_INSETS = "naboo/ime_insets"
  }
}
