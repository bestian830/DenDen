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
        
      case "ToggleLike":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let postId = args["postId"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "postId is required", details: nil))
              return
          }
          
          do {
              // ToggleLike returns *LikeResult object
              let likeResult = try c.toggleLike(postId)
              // Convert to Dictionary for Flutter
              result([
                  "isLiked": likeResult.isLiked,
                  "likeEventId": likeResult.likeEventID,
                  "postId": likeResult.postID
              ])
          } catch {
              result(FlutterError(code: "TOGGLE_LIKE_ERROR", message: error.localizedDescription, details: nil))
          }
        
      case "IsPostLiked":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let postId = args["postId"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "postId is required", details: nil))
              return
          }
          
          let isLiked = c.isPostLiked(postId)
          result(isLiked)
        
      case "GetPostStats":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let postId = args["postId"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "postId is required", details: nil))
              return
          }
          
          // Run in background to avoid blocking UI
          DispatchQueue.global(qos: .userInitiated).async {
              do {
                  let stats = try c.getPostStats(postId)
                  DispatchQueue.main.async {
                      result([
                          "postId": stats.postID,
                          "likeCount": stats.likeCount,
                          "replyCount": stats.replyCount,
                          "isLikedByMe": stats.isLikedByMe
                      ])
                  }
              } catch {
                  DispatchQueue.main.async {
                      result(FlutterError(code: "GET_STATS_ERROR", message: error.localizedDescription, details: nil))
                  }
              }
          }
        
      case "ReplyPost":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let eventId = args["eventId"] as? String,
                let content = args["content"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "eventId and content are required", details: nil))
              return
          }
          
          do {
              try c.replyPost(eventId, content: content)
              result(true)
          } catch {
              result(FlutterError(code: "REPLY_ERROR", message: error.localizedDescription, details: nil))
          }

      case "Repost":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let originalEventJson = args["originalEventJson"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "originalEventJson is required", details: nil))
              return
          }
          
          do {
              // Note: Repost returns (string, error) in Go
              var error: NSError?
              let eventId = c.repost(originalEventJson, error: &error)
              if let error = error {
                  throw error
              }
              result(eventId)
          } catch {
              result(FlutterError(code: "REPOST_ERROR", message: error.localizedDescription, details: nil))
          }

      case "QuotePost":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let content = args["content"] as? String,
                let quotedEventId = args["quotedEventId"] as? String,
                let authorPubkey = args["authorPubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "content, quotedEventId and authorPubkey are required", details: nil))
              return
          }
          
          do {
              var error: NSError?
              let eventId = c.quotePost(content, quotedEventId: quotedEventId, authorPubkey: authorPubkey, error: &error)
              if let error = error {
                  throw error
              }
              result(eventId)
          } catch {
              result(FlutterError(code: "QUOTE_ERROR", message: error.localizedDescription, details: nil))
          }
        
      case "GetPostThread":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let rootEventId = args["rootEventId"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "rootEventId is required", details: nil))
              return
          }
          
          DispatchQueue.global(qos: .userInitiated).async {
              do {
                  let threadResult = try c.getPostThread(rootEventId)
                  DispatchQueue.main.async {
                      result([
                          "rootId": threadResult.rootID,
                          "count": threadResult.count,
                          "events": threadResult.json
                      ])
                  }
              } catch {
                  DispatchQueue.main.async {
                      result(FlutterError(code: "GET_THREAD_ERROR", message: error.localizedDescription, details: nil))
                  }
              }
          }
        
      case "GetNotifications":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          let args = call.arguments as? [String: Any]
          let limit = args?["limit"] as? Int ?? 20
          
          DispatchQueue.global(qos: .userInitiated).async {
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getNotifications(limit, error: &error)
              
              if let error = error {
                  DispatchQueue.main.async {
                      result(FlutterError(code: "GET_NOTIFICATIONS_ERROR", message: error.localizedDescription, details: nil))
                  }
              } else {
                  DispatchQueue.main.async {
                      result(json ?? "[]")
                  }
              }
          }
          }
        
      case "GetUserReplies":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          let limit = args["limit"] as? Int ?? 20
          
          DispatchQueue.global(qos: .userInitiated).async {
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserReplies(pubkey, limit: limit, error: &error)
              
              if let error = error {
                  DispatchQueue.main.async {
                      result(FlutterError(code: "GET_USER_REPLIES_ERROR", message: error.localizedDescription, details: nil))
                  }
              } else {
                  DispatchQueue.main.async {
                      result(json ?? "[]")
                  }
              }
          }
          }
        
      case "fetchProfile":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          DispatchQueue.global(qos: .userInitiated).async {
              c.fetchProfile(pubkey)
              DispatchQueue.main.async {
                  result(nil)
              }
          }

      case "GetFollowing":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          DispatchQueue.global(qos: .userInitiated).async {
              let json = c.getFollowing(pubkey)
              DispatchQueue.main.async {
                  result(json)
              }
          }

      case "GetFollowers":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          DispatchQueue.global(qos: .userInitiated).async {
              let json = c.getFollowers(pubkey)
              DispatchQueue.main.async {
                  result(json)
              }
          }

      case "Follow":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let status = c.follow(pubkey, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "FOLLOW_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(status)
                  }
              }
          }

      case "Unfollow":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let status = c.unfollow(pubkey, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "UNFOLLOW_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(status)
                  }
              }
          }



      case "GetUserFeed":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          
          let limit = args["limit"] as? Int ?? 20
          
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserFeed(pubkey, limit: limit, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "GET_USER_FEED_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }

      case "GetUserPosts":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          let limit = args["limit"] as? Int ?? 20
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserPosts(pubkey, limit: limit, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "GET_USER_POSTS_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }

      case "GetUserReplies":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          let limit = args["limit"] as? Int ?? 20
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserReplies(pubkey, limit: limit, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "GET_USER_REPLIES_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }

      case "GetUserMedia":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          let limit = args["limit"] as? Int ?? 20
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserMedia(pubkey, limit: limit, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "GET_USER_MEDIA_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }

      case "GetUserHighlights":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          let limit = args["limit"] as? Int ?? 20
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserHighlights(pubkey, limit: limit, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "GET_USER_HIGHLIGHTS_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }

      case "GetUserReposts":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let pubkey = args["pubkey"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "pubkey is required", details: nil))
              return
          }
          let limit = args["limit"] as? Int ?? 20
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getUserReposts(pubkey, limit: limit, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                      result(FlutterError(code: "GET_USER_REPOSTS_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }



      case "GetSingleEvent":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
           guard let args = call.arguments as? [String: Any],
                let eventId = args["eventId"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "eventId is required", details: nil))
              return
          }
          DispatchQueue.global(qos: .userInitiated).async {
              var error: NSError?
              let json = c.getSingleEvent(eventId, error: &error)
              DispatchQueue.main.async {
                  if let error = error {
                       // Don't error out if not found, just return empty list or handle gracefully
                      result(FlutterError(code: "GET_EVENT_ERROR", message: error.localizedDescription, details: nil))
                  } else {
                      result(json ?? "[]")
                  }
              }
          }

      case "SendDirectMessage":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let receiver = args["receiver"] as? String,
                let content = args["content"] as? String else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "receiver and content required", details: nil))
              return
          }
          DispatchQueue.global(qos: .userInitiated).async {
              do {
                  try c.sendDirectMessage(receiver, content: content)
                  DispatchQueue.main.async {
                      result(true)
                  }
              } catch {
                  DispatchQueue.main.async {
                      result(FlutterError(code: "SEND_DM_ERROR", message: error.localizedDescription, details: nil))
                  }
              }
          }

      case "FetchMessages":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          let limit = (call.arguments as? [String: Any])?["limit"] as? Int ?? 50
          DispatchQueue.global(qos: .userInitiated).async {
                  // Use DebugFetchMessages with Int64 limit and manual error handling
                  var error: NSError?
                  let logs = c.debugFetchMessages(Int64(limit), error: &error)
                  if let err = error {
                      DispatchQueue.main.async {
                          print("Fetch msg error: \(err)")
                          result(FlutterError(code: "FETCH_ERROR", message: err.localizedDescription, details: nil))
                      }
                      return
                  }
                  
                  print("Native Logs: \(logs)")
                  DispatchQueue.main.async {
                      result(logs) 
                  }
              }

      case "GetConversations":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          let json = c.getConversationList()
          result(json)

      case "GetChatMessages":
          guard let c = self.client else {
              result(FlutterError(code: "CLIENT_NOT_INITIALIZED", message: "Call Initialize first", details: nil))
              return
          }
          guard let args = call.arguments as? [String: Any],
                let partner = args["partner"] as? String else {
               result(FlutterError(code: "INVALID_ARGUMENT", message: "partner pubkey required", details: nil))
               return
          }
          let json = c.getChatMessages(partner)
          result(json)

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
