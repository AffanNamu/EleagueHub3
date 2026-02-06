package com.eleaguehub.app

import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.atomic.AtomicReference

/**
 * Holds a reference to the Flutter BinaryMessenger so Android Services (overlay/FGS)
 * can talk to Dart via MethodChannel even when MainActivity is backgrounded.
 *
 * Notes:
 * - No hacks: if the process/engine is dead, messengerOrNull() will be null and we no-op.
 * - We intentionally do NOT clear on Activity destroy to avoid breaking background overlay actions
 *   when Android recreates Activity (rotation/multi-window). The reference is replaced on next attach.
 */
object FlutterEngineHolder {
    private val messengerRef = AtomicReference<BinaryMessenger?>(null)

    fun setBinaryMessenger(messenger: BinaryMessenger) {
        messengerRef.set(messenger)
    }

    fun messengerOrNull(): BinaryMessenger? = messengerRef.get()
}
