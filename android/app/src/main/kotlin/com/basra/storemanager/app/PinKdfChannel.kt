package com.basra.storemanager.app

import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * PBKDF2-HMAC-SHA256 على معالج الجهاز.
 * نفس الملح والترميز اللذين يستخدمهما Dart حتى يبقى الرمز المخزّن صالحاً،
 * لكن التحقق لا يتجمّد عدة ثوانٍ داخل Dart.
 */
object PinKdfChannel {
  private const val CHANNEL = "naboo/pin_kdf"
  private val executor = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())

  fun register(engine: FlutterEngine) {
    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      if (call.method != "pbkdf2") {
        result.notImplemented()
        return@setMethodCallHandler
      }
      val password = call.argument<String>("password") ?: ""
      val salt = call.argument<String>("salt") ?: ""
      val iterations = call.argument<Int>("iterations") ?: 0
      val keyLength = call.argument<Int>("keyLength") ?: 32
      if (password.isEmpty() || salt.isEmpty() || iterations <= 0 || keyLength !in 16..64) {
        result.error("bad_args", "invalid kdf params", null)
        return@setMethodCallHandler
      }
      executor.execute {
        try {
          val spec = PBEKeySpec(
            password.toCharArray(),
            salt.toByteArray(Charsets.UTF_8),
            iterations,
            keyLength * 8,
          )
          val encoded = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            .generateSecret(spec)
            .encoded
          spec.clearPassword()
          val out = Base64.encodeToString(encoded, Base64.URL_SAFE or Base64.NO_WRAP)
          mainHandler.post { result.success(out) }
        } catch (e: Exception) {
          mainHandler.post { result.error("kdf_failed", e.message, null) }
        }
      }
    }
  }
}
