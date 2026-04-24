package com.craigcarroll.notifyai

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.util.Log

/**
 * Receives broadcasts when the user taps an action on our summary notification.
 * Cancels the summary notification and then forwards the original app's action
 * (e.g. "Mark as read", "Reply") so the user experience is seamless.
 */
class SummaryActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pkg = intent.getStringExtra("pkg") ?: return
        val notifId = intent.getIntExtra("notifId", 0)
        val actionKey = intent.getStringExtra("actionKey") ?: return

        // Cancel our summary notification so it doesn't linger
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(notifId)
            Log.d("NotifyAI", "[info] SummaryActionReceiver: cancelled summary for $pkg (id=$notifId)")
        } catch (e: Exception) {
            Log.w("NotifyAI", "SummaryActionReceiver: failed to cancel summary: ${e.message}")
        }

        // Execute the original app's action (e.g. Mark as read, Reply)
        val originalPi = NotificationService.actionMap.remove(actionKey)
        if (originalPi != null) {
            try {
                originalPi.send()
                Log.d("NotifyAI", "[info] SummaryActionReceiver: forwarded original action for $pkg")
            } catch (e: Exception) {
                Log.w("NotifyAI", "SummaryActionReceiver: failed to forward action: ${e.javaClass.simpleName}: ${e.message}")
            }
        } else {
            Log.w("NotifyAI", "SummaryActionReceiver: original PendingIntent not found for key $actionKey")
        }
    }
}
