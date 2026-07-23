package com.basra.storemanager

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * تثبيت APK محدّث (sideload) عبر PackageInstaller ثم إعادة فتح التطبيق.
 */
class MainActivity : FlutterActivity() {
  companion object {
    private const val CHANNEL = "com.basra.storemanager/apk_installer"
    private const val ACTION_INSTALL_STATUS =
      "com.basra.storemanager.APK_INSTALL_STATUS"
  }

  private var installReceiver: BroadcastReceiver? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    val splashScreen = installSplashScreen()
    splashScreen.setOnExitAnimationListener { splashScreenView ->
      splashScreenView.remove()
    }
    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "canRequestPackageInstalls" -> {
            result.success(canRequestPackageInstalls())
          }
          "openUnknownSourcesSettings" -> {
            openUnknownSourcesSettings()
            result.success(true)
          }
          "installApk" -> {
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
              result.error("bad_args", "path مطلوب", null)
              return@setMethodCallHandler
            }
            try {
              installApk(path)
              result.success(true)
            } catch (e: Exception) {
              result.error("install_failed", e.message, null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun canRequestPackageInstalls(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      packageManager.canRequestPackageInstalls()
    } else {
      true
    }
  }

  private fun openUnknownSourcesSettings() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val intent = Intent(
        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
        Uri.parse("package:$packageName"),
      ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      startActivity(intent)
    } else {
      @Suppress("DEPRECATION")
      startActivity(
        Intent(Settings.ACTION_SECURITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
      )
    }
  }

  private fun installApk(path: String) {
    val file = File(path)
    if (!file.exists() || file.length() < 1024L) {
      throw IllegalStateException("ملف التحديث غير صالح")
    }
    if (!canRequestPackageInstalls()) {
      openUnknownSourcesSettings()
      throw IllegalStateException(
        "فعّل السماح بالتثبيت من هذا التطبيق ثم أعد المحاولة",
      )
    }

    try {
      commitViaPackageInstaller(file)
      return
    } catch (_: Exception) {
      // fallback
    }

    val uri = FileProvider.getUriForFile(
      this,
      "$packageName.fileprovider",
      file,
    )
    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, "application/vnd.android.package-archive")
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    startActivity(intent)
  }

  private fun commitViaPackageInstaller(file: File) {
    registerInstallReceiverIfNeeded()
    val installer = packageManager.packageInstaller
    val params = PackageInstaller.SessionParams(
      PackageInstaller.SessionParams.MODE_FULL_INSTALL,
    )
    val sessionId = installer.createSession(params)
    installer.openSession(sessionId).use { session ->
      file.inputStream().use { input ->
        session.openWrite("naboo-update.apk", 0, file.length()).use { out ->
          input.copyTo(out)
          session.fsync(out)
        }
      }
      val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
      } else {
        PendingIntent.FLAG_UPDATE_CURRENT
      }
      val intent = Intent(ACTION_INSTALL_STATUS).setPackage(packageName)
      val pending = PendingIntent.getBroadcast(this, sessionId, intent, flags)
      session.commit(pending.intentSender)
    }
  }

  private fun registerInstallReceiverIfNeeded() {
    if (installReceiver != null) return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
          PackageInstaller.EXTRA_STATUS,
          PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
          PackageInstaller.STATUS_PENDING_USER_ACTION -> {
            val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
              intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
              @Suppress("DEPRECATION")
              intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            }
            if (confirm != null) {
              confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
              context.startActivity(confirm)
            }
          }
          PackageInstaller.STATUS_SUCCESS -> {
            val launch = context.packageManager
              .getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
              launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP,
              )
              context.startActivity(launch)
            }
          }
        }
      }
    }
    installReceiver = receiver
    val filter = IntentFilter(ACTION_INSTALL_STATUS)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("UnspecifiedRegisterReceiverFlag")
      registerReceiver(receiver, filter)
    }
  }

  override fun onDestroy() {
    installReceiver?.let {
      try {
        unregisterReceiver(it)
      } catch (_: Exception) {
      }
    }
    installReceiver = null
    super.onDestroy()
  }
}
