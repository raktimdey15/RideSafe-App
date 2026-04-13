import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0A0A0A), // Deep sleek black
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00E676), // Neon Green accent
          surface: const Color(0xFF1A1A1A), // Sleek card color
        ),
        fontFamily: 'Roboto',
      ),
      home: const RideSafeHome(),
    );
  }
}

class RideSafeHome extends StatefulWidget {
  const RideSafeHome({super.key});

  @override
  State<RideSafeHome> createState() => _RideSafeHomeState();
}

class _RideSafeHomeState extends State<RideSafeHome> with SingleTickerProviderStateMixin {
  // Bluetooth Classic State
  BluetoothConnection? connection;
  bool isConnected = false;
  bool isConnecting = false;
  String statusText = "DISCONNECTED";

  // Sensor States
  bool isHelmetWorn = false;
  bool isAlcoholDetected = false;
  bool isDrowsy = false;

  // Data Buffer for Serial Communication
  String _dataBuffer = '';

  // Controllers
  final TextEditingController _policeController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  // TTS Engine
  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _loadNumbers();
    _checkPermissions();
    _initTTS();
  }

  Future<void> _initTTS() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.55); // Slightly slower to sound authoritativ
    await flutterTts.setVolume(1.0);      // Max volume
    await flutterTts.setPitch(1.0);
  }

  Future<void> _speakAlert(String message) async {
    await flutterTts.speak(message);
  }
  void _initAnimation() {
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    connection?.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.phone,
      ].request();
    }
  }

  Future<void> _loadNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _policeController.text = prefs.getString('police_number') ?? "999";
      _contactController.text = prefs.getString('emergency_contact') ?? "";
    });
  }

  Future<void> _saveNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('police_number', _policeController.text);
    await prefs.setString('emergency_contact', _contactController.text);
    _showSnack("Emergency Contacts Saved", const Color(0xFF00E676));
  }

  // Bluetooth classic er logic

  void _showDeviceList() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      _showError("Error getting devices: $e");
      return;
    }

    if (!mounted) return;

    // Show a sleek bottom sheet with devices
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text("SELECT HELMET MODULE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    BluetoothDevice device = devices[index];
                    return ListTile(
                      leading: const Icon(Icons.bluetooth, color: Color(0xFF00E676)),
                      title: Text(device.name ?? "Unknown Device"),
                      subtitle: Text(device.address.toString(), style: const TextStyle(color: Colors.white54)),
                      onTap: () {
                        Navigator.pop(context);
                        _connectToDevice(device);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connectToDevice(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
      statusText = "CONNECTING...";
    });

    try {
      connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        isConnected = true;
        isConnecting = false;
        statusText = "SYSTEM ONLINE";
      });

      // Listen to incoming serial stream
      connection!.input!.listen(_onDataReceived).onDone(() {
        setState(() {
          isConnected = false;
          statusText = "DISCONNECTED";
        });
      });
    } catch (e) {
      setState(() {
        isConnecting = false;
        statusText = "CONNECTION FAILED";
      });
      _showError("Could not connect to ${device.name}");
    }
  }

  void _onDataReceived(Uint8List data) {
    _dataBuffer += ascii.decode(data);

    // 1. Check for physical SOS button
    if (_dataBuffer.contains("Emergency")) {
      _triggerEmergencyProtocol();
      _dataBuffer = _dataBuffer.replaceAll("Emergency", "");
    }

    // Alcohol Check korbe
    if (_dataBuffer.contains("Alcohol")) {
      _speakAlert("WARNING! ALCOHOL DETECTED. PLEASE STOP THE VEHICLE IMMEDIATELY.");
      _showSnack("ALCOHOL DETECTED!", Colors.purpleAccent);
      setState(() { isAlcoholDetected = true; }); // Lights up the UI card
      _dataBuffer = _dataBuffer.replaceAll("Alcohol", "");
    }

    // Drowsiness Detect Korbe
    if (_dataBuffer.contains("Drowsy")) {
      _speakAlert("WARNING! DROWSINESS DETECTED. WAKE UP AND PULL OVER.");
      _showSnack("DROWSINESS DETECTED!", Colors.orangeAccent);
      setState(() { isDrowsy = true; }); // Lights up the UI card
      _dataBuffer = _dataBuffer.replaceAll("Drowsy", "");
    }

    // Alcohol+Drowsiness detect korbe
    if (_dataBuffer.contains("-")) {
      setState(() {
        isAlcoholDetected = false;
        isDrowsy = false;
      });
      _dataBuffer = _dataBuffer.replaceAll("-", "");
    }

    if (_dataBuffer.length > 50) {
      _dataBuffer = '';
    }
  }

  // EMERGENCY PROTOCOLS

  void _triggerEmergencyProtocol() {
    _showSnack("SOS DETECTED! Engaging Emergency Protocols...", Colors.redAccent);

    _makeCall();

    _sendWhatsAppLocation();
  }

  Future<void> _sendWhatsAppLocation() async {
    String contactNumber = _contactController.text.replaceAll(RegExp(r'\D'), '');

    if (contactNumber.isEmpty) {
      _showError("No WhatsApp number saved!");
      return;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError("Please turn on your phone's GPS.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

    
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // PERFECTED Google Maps Link
      String mapsLink = "https://maps.google.com/?q=${position.latitude},${position.longitude}";

      String message = Uri.encodeComponent("SOS! I am in danger. Here is my live location: $mapsLink");

      Uri whatsappAppUri = Uri.parse("whatsapp://send?phone=$contactNumber&text=$message");
      Uri whatsappWebUri = Uri.parse("https://wa.me/$contactNumber?text=$message");

      if (await canLaunchUrl(whatsappAppUri)) {
        await launchUrl(whatsappAppUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(whatsappWebUri)) {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      } else {
        _showError("Could not launch WhatsApp.");
      }

    } catch (e) {
      _showError("Location Error: $e");
    }
  }

  Future<void> _makeCall() async {
    String number = _policeController.text;
    if (number.isNotEmpty) await FlutterPhoneDirectCaller.callNumber(number);
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  void _showSnack(String msg, Color color) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("R I D E S A F E", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 22)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Sleek Connection Button
              Center(
                child: GestureDetector(
                  onTap: isConnected || isConnecting ? null : _showDeviceList,
                  child: AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: isConnected ? 1.0 : _scaleAnimation.value,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF111111),
                            border: Border.all(
                              color: isConnected ? const Color(0xFF00E676) : (isConnecting ? Colors.orange : Colors.blueAccent),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isConnected ? const Color(0xFF00E676).withOpacity(0.3) : Colors.blueAccent.withOpacity(0.3),
                                blurRadius: 40,
                                spreadRadius: 10,
                              )
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                              size: 70,
                              color: isConnected ? const Color(0xFF00E676) : Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 25),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isConnected ? const Color(0xFF00E676) : Colors.white54,
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 40),

    
              Row(
                children: [
                  Expanded(child: _buildSensorCard("HELMET", isHelmetWorn, Icons.sports_motorsports, Colors.blue)),
                  const SizedBox(width: 15),
                  Expanded(child: _buildSensorCard("SOBRIETY", !isAlcoholDetected, Icons.local_bar, Colors.purpleAccent)),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(child: _buildSensorCard("ALERTNESS", !isDrowsy, Icons.remove_red_eye, Colors.orangeAccent)),
                  const SizedBox(width: 15),
                  Expanded(
                    child: GestureDetector(
                      onTap: _triggerEmergencyProtocol,
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          border: Border.all(color: Colors.redAccent, width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning, color: Colors.redAccent, size: 35),
                            SizedBox(height: 8),
                            Text("MANUAL SOS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // 3. Settings Card
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("EMERGENCY CONFIG", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _buildTextField(_policeController, "Police Number", Icons.local_police_outlined),
                    const SizedBox(height: 15),
                    _buildTextField(_contactController, "WhatsApp Contact", Icons.chat_bubble_outline),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveNumbers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676).withOpacity(0.1),
                          foregroundColor: const Color(0xFF00E676),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: const BorderSide(color: Color(0xFF00E676)),
                          ),
                        ),
                        child: const Text("SAVE SECURELY", style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard(String title, bool isOk, IconData icon, Color accentColor) {
    bool active = isConnected;
    Color statusColor = active ? (isOk ? const Color(0xFF00E676) : Colors.redAccent) : Colors.white24;

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.5)),
        boxShadow: active && !isOk ? [BoxShadow(color: Colors.redAccent.withOpacity(0.2), blurRadius: 15)] : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: active ? accentColor : Colors.white24, size: 32),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: active ? Colors.white : Colors.white24, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF0A0A0A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}
