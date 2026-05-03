package com.craigcarroll.notifyai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class DigestReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DIGEST = "com.craigcarroll.notifyai.ACTION_DIGEST"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DIGEST) return
        val pkg = intent.getStringExtra("package_name")
        Log.d("NotifyAI", "[info] DigestReceiver triggered for pkg=$pkg")
        val service = NotificationService.getInstance()
        if (service != null) {
            if (pkg != null) {
                service.flushPackage(pkg)
            } else {
                service.flushAllPackages()
            }
        } else {
            Log.w("NotifyAI", "[warn] DigestReceiver: NotificationService not running")
        }
    }
}
