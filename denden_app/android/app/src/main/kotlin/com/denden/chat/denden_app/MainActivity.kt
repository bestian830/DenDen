package com.denden.chat.denden_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import mobile.Mobile
import mobile.StringCallback

class MainActivity: FlutterActivity(), StringCallback {
    private val METHOD_CHANNEL = "com.denden.mobile/bridge"
    private val EVENT_CHANNEL = "com.denden.mobile/events"
    
    // Persistent Go client instance
    private var client: mobile.DenDenClient? = null
    
    // Event sink for streaming messages to Flutter
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up MethodChannel for method calls
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "Initialize" -> {
                    try {
                        val path = context.filesDir.absolutePath
                        client = Mobile.newDenDenClient(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                
                "GetIdentity" -> {
                    try {
                        val c = client
                        if (c == null) {
                            result.error("CLIENT_NOT_INITIALIZED", "Call Initialize first", null)
                            return@setMethodCallHandler
                        }
                        val json = c.identityJSON
                        result.success(json)
                    } catch (e: Exception) {
                        result.error("GET_IDENTITY_ERROR", e.message, null)
                    }
                }
                
                "ConnectToDefault" -> {
                    try {
                        val c = client
                        if (c == null) {
                            result.error("CLIENT_NOT_INITIALIZED", "Call Initialize first", null)
                            return@setMethodCallHandler
                        }
                        
                        // Connect to default seed relays
                        c.connectToDefault()
                        
                        // Start listening immediately after connection
                        c.startListening(this)
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CONNECT_ERROR", e.message, null)
                    }
                }
                
                "GetProfile" -> {
                    try {
                        val c = client
                        if (c == null) {
                            result.error("CLIENT_NOT_INITIALIZED", "Call Initialize first", null)
                            return@setMethodCallHandler
                        }
                        
                        val pubkey = call.argument<String>("pubkey")
                        if (pubkey == null) {
                            result.error("INVALID_ARGUMENT", "Pubkey is required", null)
                            return@setMethodCallHandler
                        }
                        
                        val profileJson = c.getProfile(pubkey)
                        result.success(profileJson)
                    } catch (e: Exception) {
                        result.error("GET_PROFILE_ERROR", e.message, null)
                    }
                }
                
                "PublishTextNote" -> {
                    try {
                        val c = client
                        if (c == null) {
                            result.error("CLIENT_NOT_INITIALIZED", "Call Initialize first", null)
                            return@setMethodCallHandler
                        }
                        
                        val content = call.argument<String>("content")
                        if (content == null) {
                            result.error("INVALID_ARGUMENT", "Content is required", null)
                            return@setMethodCallHandler
                        }
                        
                        c.publishTextNote(content)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PUBLISH_ERROR", e.message, null)
                    }
                }
                
                "PublishMetadata" -> {
                    try {
                        val c = client
                        if (c == null) {
                            result.error("CLIENT_NOT_INITIALIZED", "Call Initialize first", null)
                            return@setMethodCallHandler
                        }
                        
                        val name = call.argument<String>("name")
                        val about = call.argument<String>("about")
                        val picture = call.argument<String>("picture")
                        
                        if (name == null || about == null || picture == null) {
                            result.error("INVALID_ARGUMENT", "Name, about, and picture are required", null)
                            return@setMethodCallHandler
                        }
                        
                        c.publishMetadata(name, about, picture)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PUBLISH_METADATA_ERROR", e.message, null)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Set up EventChannel for streaming messages
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }
    
    // StringCallback implementation - called by Go when new message arrives
    override fun onMessage(json: String?) {
        json?.let {
            // Send message to Flutter through EventChannel
            runOnUiThread {
                eventSink?.success(it)
            }
        }
    }
    
    override fun onDestroy() {
        client?.close()
        client = null
        eventSink = null
        super.onDestroy()
    }
}
