import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  runApp(const RideSafeApp());
}

class RideSafeApp extends StatelessWidget {
  const RideSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RideSafe',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFD32F2F),
        scaffoldBackgroundColor: const Color(0xFF000000), // Pitch black for OLED
        useMaterial3: true,
        textTheme: GoogleFonts.bebasNeueTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final String targetDeviceName = "RideSafe_ESP32";
  final String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  bool isScanning = false;
  List<String> emergencyContacts = [];
  final TextEditingController _contactController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _checkPermissions();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => emergencyContacts = prefs.getStringList('emergency_contacts') ?? []);
  }

  Future<void> _checkPermissions() async {
    // Request all necessary permissions for Android 12+
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location
    ].request();
  }

  void toggleScan() async {
    if (isScanning) {
      await FlutterBluePlus.stopScan();
      setState(() => isScanning = false);
      return;
    }

    setState(() => isScanning = true);

    // Start Scan
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Listen to results
    var subscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == targetDeviceName) {
          FlutterBluePlus.stopScan();
          connectToDevice(r.device);
          break;
        }
      }
    });

    // Auto-stop scanning logic
    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && mounted) {
        setState(() => isScanning = false);
        subscription.cancel();
      }
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() => connectedDevice = device);

      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString() == serviceUUID) {
          for (BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid.toString() == characteristicUUID) {
              targetCharacteristic = c;
              await c.setNotifyValue(true);
              c.lastValueStream.listen((value) {
                if (value.isNotEmpty && value[0] == 1) triggerSOS();
              });
            }
          }
        }
      }
    } catch (e) {
      print("Connection Error: $e");
    }
  }

  void triggerSOS() async {
    if (emergencyContacts.isEmpty) return;
    final Uri launchUri = Uri(scheme: 'tel', path: emergencyContacts.first);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }

  // --- UI SECTION ---
  @override
  Widget build(BuildContext context) {
    bool isConnected = connectedDevice != null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            children: [
              // 1. Header
              const Text("RIDE SAFE", style: TextStyle(fontSize: 42, color: Colors.redAccent, letterSpacing: 2)),
              const SizedBox(height: 30),

              // 2. Status Card
              InkWell(
                onTap: isConnected ? null : toggleScan,
                child: Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isConnected
                            ? [Colors.green[900]!, Colors.green[600]!]
                            : [Colors.red[900]!, Colors.red[600]!],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(color: (isConnected ? Colors.green : Colors.red).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))
                      ]
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isConnected ? "CONNECTED" : (isScanning ? "SCANNING..." : "DISCONNECTED"),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text(isConnected ? "System Armed & Ready" : "Tap to Connect Bike",
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70)),
                        ],
                      ),
                      // Dynamic Icon Logic
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(50)),
                        child: isScanning
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Icon(isConnected ? Icons.check_circle : Icons.bluetooth_searching, color: Colors.white, size: 28),
                      )
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // 3. Main SOS Button
              GestureDetector(
                onTap: triggerSOS,
                child: Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFD32F2F),
                      boxShadow: [
                        BoxShadow(color: Colors.red.withOpacity(0.6), blurRadius: 60, spreadRadius: 10),
                      ],
                      border: Border.all(color: Colors.white12, width: 8)
                  ),
                  child: const Center(
                    child: Text("SOS", style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.05, 1.05), duration: 2.seconds),

              const Spacer(),

              // 4. Contacts Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("EMERGENCY CONTACTS", style: TextStyle(fontSize: 22, color: Colors.white70)),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.redAccent, size: 32),
                    onPressed: _showAddContact,
                  )
                ],
              ),
              const SizedBox(height: 15),

              // Contacts List
              if (emergencyContacts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning, color: Colors.amber),
                      const SizedBox(width: 10),
                      Text("No Contacts Added", style: GoogleFonts.poppins(color: Colors.grey)),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: emergencyContacts.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                          leading: const Icon(Icons.phone, color: Colors.white),
                          title: Text(emergencyContacts[index], style: GoogleFonts.poppins(fontSize: 16)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                emergencyContacts.removeAt(index);
                                _saveContacts();
                              });
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddContact() {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Add Number", style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: _contactController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: "017xxxxxxxx",
              hintStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.red)),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  if (_contactController.text.isNotEmpty) {
                    setState(() => emergencyContacts.add(_contactController.text));
                    _saveContacts();
                    _contactController.clear();
                    Navigator.pop(context);
                  }
                },
                child: const Text("SAVE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
            )
          ],
        )
    );
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emergency_contacts', emergencyContacts);
  }
}