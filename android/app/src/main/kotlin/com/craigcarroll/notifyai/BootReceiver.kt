package com.craigcarroll.notifyai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // NotificationListenerService is automatically restarted by Android on boot
        // if the permission is granted. Reschedule digest alarms if enabled.
        val service = NotificationService.getInstance()
        if (service != null) {
            service.scheduleDigestAlarms()
        }
    }
}
