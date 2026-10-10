package com.pancyo.aiastrology

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** A foreground-only, explicit-start looping background-music player. */
internal class ManualBgmPlayer(context: Context) {
    companion object {
        const val METHOD_CHANNEL = "com.pancyo.aiastrology/manual_bgm"
        const val EVENT_CHANNEL = "com.pancyo.aiastrology/manual_bgm/events"
        private const val DEFAULT_VOLUME = 0.35
    }

    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    private var eventSink: EventChannel.EventSink? = null
    private var player: MediaPlayer? = null
    private var playerGeneration = 0L
    private var focusGeneration = 0L
    private var focusRequest: AudioFocusRequest? = null
    private var disposed = false
    private var playing = false
    private var busy = false
    private var volume = DEFAULT_VOLUME
    private var errorCode: String? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        checkMainThread()
        if (disposed) return
        eventSink = sink
        if (sink != null) publishState()
    }

    fun getState(): Map<String, Any?> {
        checkMainThread()
        return state()
    }

    fun invalidRequest(code: String): Map<String, Any?> {
        checkMainThread()
        return state().toMutableMap().apply { this["errorCode"] = code }
    }

    /** Starts only in response to an explicit foreground user action. */
    fun play(loop: Boolean): Map<String, Any?> {
        checkMainThread()
        if (disposed) return stateWithError("player_unavailable")
        if (!loop) return stateWithError("loop_required")
        if (playing || busy) return state()

        errorCode = null
        if (!requestAudioFocus()) {
            errorCode = "audio_focus_denied"
            publishState()
            return state()
        }

        val attempt = ++playerGeneration
        busy = true
        playing = false
        publishState()

        var candidate: MediaPlayer? = null
        try {
            candidate = MediaPlayer()
            player = candidate
            candidate.setAudioAttributes(audioAttributes)
            candidate.isLooping = true
            candidate.setVolume(volume.toFloat(), volume.toFloat())
            candidate.setOnPreparedListener { prepared ->
                if (!isCurrent(attempt, prepared)) {
                    releasePlayer(prepared)
                    return@setOnPreparedListener
                }
                try {
                    prepared.isLooping = true
                    prepared.setVolume(volume.toFloat(), volume.toFloat())
                    prepared.start()
                    playing = true
                    busy = false
                    errorCode = null
                    publishState()
                } catch (_: Exception) {
                    failAttempt(attempt, "playback_failed", prepared)
                }
            }
            candidate.setOnErrorListener { failed, _, _ ->
                if (isCurrent(attempt, failed)) {
                    failAttempt(
                        attempt,
                        if (busy) "prepare_failed" else "playback_failed",
                        failed,
                    )
                }
                true
            }
            candidate.setOnCompletionListener { completed ->
                if (isCurrent(attempt, completed)) {
                    failAttempt(attempt, "playback_ended", completed)
                }
            }

            val source = Uri.parse("android.resource://${appContext.packageName}/${R.raw.spring_wind}")
            candidate.setDataSource(appContext, source)
            candidate.prepareAsync()
        } catch (_: android.content.res.Resources.NotFoundException) {
            failAttempt(attempt, "asset_unavailable", candidate)
        } catch (_: IllegalArgumentException) {
            failAttempt(attempt, "asset_unavailable", candidate)
        } catch (_: Exception) {
            failAttempt(
                attempt,
                if (candidate == null) "player_unavailable" else "prepare_failed",
                candidate,
            )
        }
        return state()
    }

    fun stop(): Map<String, Any?> {
        checkMainThread()
        if (disposed) return state()
        stopInternal(publish = true)
        return state()
    }

    /** Sets this player's scalar volume only; the device's system volume is untouched. */
    fun setVolume(value: Double): Map<String, Any?> {
        checkMainThread()
        require(!disposed) { "player_unavailable" }
        require(!value.isNaN() && !value.isInfinite() && value in 0.0..1.0) {
            "volume_out_of_range"
        }
        volume = value
        val current = player
        if (playing && current != null) {
            try {
                current.setVolume(value.toFloat(), value.toFloat())
            } catch (_: Exception) {
                failAttempt(playerGeneration, "playback_failed", current)
                return state()
            }
        }
        publishState()
        return state()
    }

    /** Called when the Activity is destroyed; playback is never restored automatically. */
    fun dispose() {
        checkMainThread()
        if (disposed) return
        stopInternal(publish = false)
        disposed = true
        eventSink = null
    }

    private fun requestAudioFocus(): Boolean {
        val focusToken = ++focusGeneration
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            if (focusToken != focusGeneration || disposed) return@OnAudioFocusChangeListener
            if (change != AudioManager.AUDIOFOCUS_GAIN) {
                // Any interruption, including a call or duck request, requires a new user tap.
                stopInternal(publish = true)
            }
        }
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(audioAttributes)
            .setAcceptsDelayedFocusGain(false)
            .setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener(listener, mainHandler)
            .build()
        focusRequest = request
        return try {
            if (audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                true
            } else {
                if (focusRequest === request) focusRequest = null
                focusGeneration += 1
                false
            }
        } catch (_: Exception) {
            if (focusRequest === request) focusRequest = null
            focusGeneration += 1
            false
        }
    }

    private fun stopInternal(publish: Boolean) {
        playerGeneration += 1
        val oldPlayer = player
        player = null
        playing = false
        busy = false
        errorCode = null
        releasePlayer(oldPlayer)
        abandonAudioFocus()
        if (publish) publishState()
    }

    private fun failAttempt(attempt: Long, code: String, failedPlayer: MediaPlayer?) {
        if (disposed || attempt != playerGeneration) {
            if (failedPlayer !== player) releasePlayer(failedPlayer)
            return
        }
        val activePlayer = player
        if (failedPlayer != null && activePlayer != null && failedPlayer !== activePlayer) {
            releasePlayer(failedPlayer)
            return
        }
        playerGeneration += 1
        player = null
        playing = false
        busy = false
        errorCode = code
        releasePlayer(activePlayer ?: failedPlayer)
        abandonAudioFocus()
        publishState()
    }

    private fun isCurrent(attempt: Long, candidate: MediaPlayer): Boolean =
        !disposed && attempt == playerGeneration && player === candidate

    private fun abandonAudioFocus() {
        val request = focusRequest
        focusRequest = null
        focusGeneration += 1
        if (request != null) {
            try {
                audioManager.abandonAudioFocusRequest(request)
            } catch (_: Exception) {
                // No playback or focus state is restored if the platform rejects cleanup.
            }
        }
    }

    private fun releasePlayer(target: MediaPlayer?) {
        if (target == null) return
        try { target.setOnPreparedListener(null) } catch (_: Exception) {}
        try { target.setOnCompletionListener(null) } catch (_: Exception) {}
        try { target.setOnErrorListener(null) } catch (_: Exception) {}
        try { target.release() } catch (_: Exception) {}
    }

    private fun state(): Map<String, Any?> = linkedMapOf(
        "playing" to playing,
        "busy" to busy,
        "errorCode" to errorCode,
        "volume" to volume,
    )

    private fun stateWithError(code: String): Map<String, Any?> = linkedMapOf(
        "playing" to false,
        "busy" to false,
        "errorCode" to code,
        "volume" to volume,
    )

    private fun publishState() {
        val sink = eventSink ?: return
        try {
            sink.success(state())
        } catch (_: Exception) {
            eventSink = null
        }
    }

    private fun checkMainThread() {
        check(Looper.myLooper() == Looper.getMainLooper()) { "ManualBgmPlayer must run on the main thread" }
    }
}
