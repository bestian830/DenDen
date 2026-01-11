import UIKit
import Flutter
import DenDen

@main
@objc class AppDelegate: FlutterAppDelegate, MobileStringCallbackProtocol {
  // Persistent Go client instance
  var client: MobileDenDenClient?
  
  // Event sink for streaming messages to Flutter
  var eventSink: FlutterEventSink?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Set up MethodChannel
    let methodChannel = FlutterMethodChannel(name: "com.denden.mobile/bridge",
                                            binaryMessenger: controller.binaryMessenger)
    
    methodChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      guard let self = self else {
        result(FlutterError(code: "INTERNAL_ERROR", message: "AppDelegate is nil", details: nil))
        return
      }
      
      switch call.method {
      case "Initialize":
          let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
          
          var error: NSError?
          let newClient = MobileNewDenDenClient(documentsPath, &error)
          
          if let err = error {
              result(FlutterError(code: "INIT_ERROR", message: err.localizedDescription, details: nil))
              return
          }
          
          guard let c = newClient else {
              result(FlutterError(code: "INIT_ERROR", message: "Client is null", details: nil))
              return
          }
          
          self.client = c
          result(true)
        
      case "GetIdentity":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          let identityJSON = c.getIdentityJSON()
          result(identityJSON)
        
      case "ConnectToDefault":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          do {
              // 1. Connect to default seed relays
              try c.connectToDefault()
              
              // 2. Start listening immediately
              // Swift 自动处理 error 参数，只需用 try
              try c.startListening(self)
              
              result(true)
          } catch {
              result(FlutterError(code: "CONNECT_ERROR", message: error.localizedDescription, details: nil))
          }
        
      case "GetProfile":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "Pubkey is required", details: nil))
              return
          }
          
          let profileJson = c.getProfile(pubkey)
          result(profileJson)
        
      case "PublishTextNote":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let content = args["content"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "Content is required", details: nil))
              return
          }
          
          // Extract tags if provided and convert to JSON string
          var tagsJSON = ""
          if let tags = args["tags"] as? [[String]] {
              if let jsonData = try? JSONSerialization.data(withJSONObject: tags),
                 let jsonString = String(data: jsonData, encoding: .utf8) {
                  tagsJSON = jsonString
                  print("📍 iOS Bridge: Sending tags to Go: \(tagsJSON)")
              }
          }
          
          do {
              // GoMobile generates: publishTextNote(_ content: String, tagsJSON: String)
              // Call with named parameter for second argument
              try c.publishTextNote(content, tagsJSON: tagsJSON)
              result(true)
          } catch {
              result(FlutterError(code: "PUBLISH_ERROR", message: error.localizedDescription, details: nil))
          }
        
      case "PublishMetadata":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          // Go now expects a single JSON string argument containing all fields
          guard let args = call.arguments as? [String: Any],
                let jsonString = args["metadataJson"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "metadataJson string is required", details: nil))
              return
          }
          
          do {
              // Call the updated Go method with the single JSON string
              try c.publishMetadata(jsonString)
              result(true)
          } catch {
              result(FlutterError(code: "PUBLISH_METADATA_ERROR", message: error.localizedDescription, details: nil))
          }
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    // Set up EventChannel
    let eventChannel = FlutterEventChannel(name: "com.denden.mobile/events",
                                          binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MobileStringCallbackProtocol implementation
  func onMessage(_ json: String?) {
      guard let message = json else { return }
      
      // Send message to Flutter through EventChannel
      DispatchQueue.main.async { [weak self] in
          self?.eventSink?(message)
      }
  }
  
  override func applicationWillTerminate(_ application: UIApplication) {
    if let c = client {
      try? c.close()
      client = nil
    }
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
