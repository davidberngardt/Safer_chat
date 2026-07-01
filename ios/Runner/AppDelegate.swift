import UIKit
import Flutter
import Firebase
import flutter_local_notifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Инициализация Firebase
        FirebaseApp.configure()
        
        // Настройка уведомлений
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
        }
        
        // Регистрация для удаленных уведомлений
        UIApplication.shared.registerForRemoteNotifications()
        
        // Настройка FlutterLocalNotifications
        FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
        }
        
        // Регистрация для VoIP пушей
        flutter_callkit_incoming.registerPlugin()
        
        // Регистрация всех плагинов
        GeneratedPluginRegistrant.register(with: self)
        
        // Обработка опций запуска (для случая, когда приложение запущено из уведомления)
        if #available(iOS 10.0, *) {
            // Этот код уже обрабатывается через UNUserNotificationCenterDelegate
        } else {
            // Для старых версий iOS
            if let notification = launchOptions?[.remoteNotification] as? [String: AnyObject] {
                // Обработка уведомления
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.handleRemoteNotification(notification)
                }
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Обработка APNs токена
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Проксируем APNs токен в Firebase
        Messaging.messaging().apnsToken = deviceToken
        
        // Отправляем токен в Flutter через канал
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.example.safe_chat/notification",
                binaryMessenger: controller.binaryMessenger
            )
            let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
            channel.invokeMethod("onApnsToken", arguments: tokenString)
        }
        
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    // Обработка ошибок регистрации
    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    // Обработка получения уведомления когда приложение в фоне (нажатие на уведомление)
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Получаем данные уведомления
        let userInfo = response.notification.request.content.userInfo
        
        // Логируем получение уведомления
        if let messageID = userInfo["gcm.message_id"] {
            print("📱 Received notification with ID: \(messageID)")
        }
        
        // Отправляем данные в Flutter
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.example.safe_chat/notification",
                binaryMessenger: controller.binaryMessenger
            )
            channel.invokeMethod("onNotificationTap", arguments: userInfo)
        }
        
        completionHandler()
    }
    
    // Обработка получения уведомления когда приложение на переднем плане
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("📱 Received foreground notification: \(userInfo)")
        
        // Показываем уведомление даже когда приложение открыто
        if #available(iOS 14.0, *) {
            completionHandler([[.banner, .sound, .badge, .list]])
        } else {
            completionHandler([[.alert, .sound, .badge]])
        }
    }
    
    // Обработка удаленных уведомлений (для iOS 9 и ниже)
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Проверяем, является ли это VoIP уведомлением
        if let pushType = userInfo["pushType"] as? String, pushType == "voip" {
            print("📱 Received VoIP push")
            // Обработка VoIP через CallKit
            flutter_callkit_incoming.sharedInstance?.didReceiveIncomingPush?(userInfo)
        }
        
        // Отправляем данные в Flutter
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.example.safe_chat/notification",
                binaryMessenger: controller.binaryMessenger
            )
            channel.invokeMethod("onRemoteMessage", arguments: userInfo)
        }
        
        completionHandler(.newData)
    }
    
    // Вспомогательный метод для обработки уведомлений на старых iOS
    private func handleRemoteNotification(_ userInfo: [String: AnyObject]) {
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "com.example.safe_chat/notification",
                binaryMessenger: controller.binaryMessenger
            )
            channel.invokeMethod("onNotificationLaunch", arguments: userInfo)
        }
    }
}