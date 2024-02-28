import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Got a message in the background!');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class ReceivedNotification {
  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._();
  NotificationHelper._();
  static NotificationHelper get instance => _instance;

  late FirebaseMessaging messaging;
  late AndroidNotificationChannel channel;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  late StreamController<ReceivedNotification>
      _didReceiveLocalNotificationStream;
  late StreamController<String?> _selectNotificationStream;

  Future<void> setupFlutterNotifications() async {
    messaging = FirebaseMessaging.instance;
    channel = const AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Channel for important notifications',
      importance: Importance.max,
    );

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: _handleDidReceiveLocalNotification,
    );

    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleDidReceiveNotificationResponse,
    );

    await _requestPermissions();

    _setupMessageListeners();
  }

  void _handleDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) async {
    _didReceiveLocalNotificationStream.add(
      ReceivedNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  void _handleDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) {
    _selectNotificationStream.add(notificationResponse.payload);
  }

  Future<void> _requestPermissions() async {
    await messaging.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      sound: true,
    );

    if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } else {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();
    }
  }

  void _setupMessageListeners() {
    _didReceiveLocalNotificationStream =
        StreamController<ReceivedNotification>.broadcast();
    _selectNotificationStream = StreamController<String?>.broadcast();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Got a message in the foreground!');
      if (message.notification != null) {
        _showLocalNotification(message);
        _handleForegroundMessage(message);
      }
    });

    _handleBackgroundMessage();
    _handleTerminatedMessage();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _selectNotificationStream.stream.listen((String? payload) {
      log('selectNotificationStream.listen');
      _notificationTapped(message);
    });
  }

  void _handleBackgroundMessage() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _notificationTapped(message);
    });
  }

  Future<void> _handleTerminatedMessage() async {
    RemoteMessage? initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _notificationTapped(initialMessage);
    }
  }

  void _notificationTapped(RemoteMessage message) {
    if (message.notification != null) {
      log('Notification tapped  ${message.notification!.title}');
      // You can also handle navigation or any other action here
    }
  }

  void _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      await flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: 'Channel for important notifications',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: const DarwinNotificationDetails(
            categoryIdentifier: 'plainCategory',
          ),
        ),
      );
    }
  }

  Future<String> get getFcmToken async => await messaging.getToken() ?? '';
}
