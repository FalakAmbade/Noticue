// =========================================================================
// RemindMe - Simple Reminder App
// -------------------------------------------------------------------------
// Everything is kept in ONE file on purpose, so every line can be explained
// easily during a viva. No code generation, no complex state management.
//
// What this app does:
//   1. Shows a list of reminders (title + date/time).
//   2. Lets you add a new reminder using a simple form.
//   3. Lets you delete a reminder.
//   4. Saves reminders to the phone using Hive (a simple local database).
//   5. Schedules a local notification for each reminder's date/time.
//
// Packages used (add these to pubspec.yaml under dependencies):
//   hive: ^2.2.3
//   hive_flutter: ^1.1.0
//   flutter_local_notifications: ^17.2.3
//   timezone: ^0.9.4
//   intl: ^0.19.0
// =========================================================================

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

// -------------------------------------------------------------------------
// A global variable that lets any part of the app show notifications.
// Kept simple as a single shared object instead of a complex service class.
// -------------------------------------------------------------------------
final FlutterLocalNotificationsPlugin notificationsPlugin =
FlutterLocalNotificationsPlugin();

// Name of the Hive "box" (think of it like a labeled storage container).
const String reminderBoxName = 'reminders';

// -------------------------------------------------------------------------
// main() runs first. It sets up Hive and notifications before the app
// starts, since both need a little bit of setup ("initialization").
// -------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Step 1: Start Hive and open the box we will store reminders in.
  await Hive.initFlutter();
  await Hive.openBox(reminderBoxName);

  // Step 2: Set up timezone data. Needed so notifications fire at the
  // correct local time on the device.
  tzData.initializeTimeZones();

  // Step 3: Set up the notifications plugin with basic Android settings.
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
  InitializationSettings(android: androidSettings);
  await notificationsPlugin.initialize(initSettings);

  // Step 4: Ask for notification permission (required on Android 13+).
  // On older Android versions this simply does nothing harmful.
  await Permission.notification.request();

  runApp(const RemindMeApp());
}

// -------------------------------------------------------------------------
// Root widget of the app. Sets up the theme and the home screen.
// -------------------------------------------------------------------------
class RemindMeApp extends StatelessWidget {
  const RemindMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemindMe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6F4E37), // coffee brown
        scaffoldBackgroundColor: const Color(0xFFFAF3E7), // warm cream
      ),
      home: const ReminderHomePage(),
    );
  }
}

// -------------------------------------------------------------------------
// Home screen: shows the list of reminders and a button to add new ones.
// -------------------------------------------------------------------------
class ReminderHomePage extends StatefulWidget {
  const ReminderHomePage({super.key});

  @override
  State<ReminderHomePage> createState() => _ReminderHomePageState();
}

class _ReminderHomePageState extends State<ReminderHomePage> {
  // We keep a direct reference to the Hive box so we can read/write to it.
  final Box reminderBox = Hive.box(reminderBoxName);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RemindMe'),
        backgroundColor: const Color(0xFF6F4E37),
        foregroundColor: Colors.white,
      ),
      // ValueListenableBuilder automatically rebuilds the list whenever
      // the Hive box changes (add/delete) - no manual setState needed
      // for the list itself.
      body: ValueListenableBuilder(
        valueListenable: reminderBox.listenable(),
        builder: (context, Box box, _) {
          if (box.isEmpty) {
            return const Center(
              child: Text(
                'No reminders yet.\nTap + to add one.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.brown),
              ),
            );
          }

          // Get all reminder keys (each key is a unique reminder id).
          final List keys = box.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: keys.length,
            itemBuilder: (context, index) {
              final key = keys[index];
              final Map reminder = Map.from(box.get(key));

              final String title = reminder['title'];
              final DateTime dateTime = DateTime.parse(reminder['dateTime']);
              final String formattedTime =
              DateFormat('EEE, MMM d - hh:mm a').format(dateTime);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(formattedTime),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.brown),
                    onPressed: () => _deleteReminder(key),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6F4E37),
        onPressed: _openAddReminderSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Deletes a reminder from Hive and cancels its scheduled notification.
  // -----------------------------------------------------------------------
  void _deleteReminder(dynamic key) async {
    // The notification id is stored alongside the reminder so we can
    // cancel the exact notification tied to this reminder.
    final Map reminder = Map.from(reminderBox.get(key));
    final int notificationId = reminder['notificationId'];

    await notificationsPlugin.cancel(notificationId);
    await reminderBox.delete(key);
  }

  // -----------------------------------------------------------------------
  // Opens a bottom sheet with a simple form to add a new reminder.
  // -----------------------------------------------------------------------
  void _openAddReminderSheet() {
    final TextEditingController titleController = TextEditingController();
    DateTime? selectedDateTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // StatefulBuilder lets this bottom sheet update its own small bit
        // of state (the picked date/time) without touching the whole page.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'New Reminder',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Reminder title',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      selectedDateTime == null
                          ? 'Pick date & time'
                          : DateFormat('EEE, MMM d - hh:mm a')
                          .format(selectedDateTime!),
                    ),
                    onPressed: () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );

                      // If-else check: only continue if the user actually
                      // picked a date instead of cancelling.
                      if (pickedDate != null) {
                        final TimeOfDay? pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );

                        if (pickedTime != null) {
                          setSheetState(() {
                            selectedDateTime = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );
                          });
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6F4E37),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      final String title = titleController.text.trim();

                      // Simple validation using if-else, easy to explain.
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a title')),
                        );
                      } else if (selectedDateTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please pick a date & time')),
                        );
                      } else {
                        _saveReminder(title, selectedDateTime!);
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save Reminder'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Saves a reminder into Hive and schedules its notification.
  // -----------------------------------------------------------------------
  void _saveReminder(String title, DateTime dateTime) async {
    // Notification id must be a unique number. Using the current time in
    // milliseconds is a simple way to get a unique-enough id.
    final int notificationId =
    DateTime.now().millisecondsSinceEpoch.remainder(100000);

    // A reminder is stored simply as a Map (like a small dictionary).
    // This avoids needing a custom Hive adapter / code generation.
    final Map<String, dynamic> reminder = {
      'title': title,
      'dateTime': dateTime.toIso8601String(),
      'notificationId': notificationId,
    };

    // Hive.add() automatically assigns a key and stores the value.
    await reminderBox.add(reminder);

    await _scheduleNotification(notificationId, title, dateTime);
  }

  // -----------------------------------------------------------------------
  // Schedules a local notification to fire at the reminder's date/time.
  // -----------------------------------------------------------------------
  Future<void> _scheduleNotification(
      int id, String title, DateTime dateTime) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'reminder_channel', // channel id
      'Reminders', // channel name
      channelDescription: 'Notifications for RemindMe reminders',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidDetails);

    await notificationsPlugin.zonedSchedule(
      id,
      'RemindMe',
      title,
      tz.TZDateTime.from(dateTime, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}