import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() => runApp(const MaterialApp(home: GpsNmeaApp()));

class GpsNmeaApp extends StatefulWidget {
  const GpsNmeaApp({super.key});

  @override
  State<GpsNmeaApp> createState() => _GpsNmeaAppState();
}

class _GpsNmeaAppState extends State<GpsNmeaApp> {
  bool _isStreaming = false;
  String _lastGpsData = "Odotetaan GPS-tietoa...";
  StreamSubscription<Position>? _positionStream;
  RawDatagramSocket? _sendSocket;
  int _packetCount = 0;
  bool _gpsActive = false;

  // Lähetys asetukset
  final TextEditingController _sendIpController =
      TextEditingController(text: "192.168.1.255");
  final TextEditingController _sendPortController =
      TextEditingController(text: "10110");

  @override
  void initState() {
    super.initState();
    _startGpsMonitoring();
  }

  @override
  void dispose() {
    _sendIpController.dispose();
    _sendPortController.dispose();
    _positionStream?.cancel();
    _sendSocket?.close();
    super.dispose();
  }

  Future<void> _startGpsMonitoring() async {
    // Tarkista GPS-luvat
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _lastGpsData = "GPS-lupa evätty!";
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _lastGpsData = "GPS-lupa evätty pysyvästi! Salli lupa asetuksista.";
      });
      return;
    }

    try {
      // Aloita GPS-kuuntelu
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen((Position position) {
        _updateGpsData(position);
      });

      setState(() {
        _gpsActive = true;
        _lastGpsData = "GPS käynnissä, odotetaan signaalia...";
      });
    } catch (e) {
      setState(() {
        _lastGpsData = "GPS-virhe: $e";
      });
    }
  }

  void _updateGpsData(Position position) {
    // Luodaan NMEA RMC-tyylinen lause
    String nmea = _generateRMC(position);
    String humanReadable = _generateHumanReadable(position);

    // Lähetetään verkkoon vain jos striimaus on päällä
    if (_isStreaming && _sendSocket != null) {
      try {
        String sendIp = _sendIpController.text;
        int sendPort = int.parse(_sendPortController.text);

        _sendSocket?.send(
          utf8.encode(nmea),
          InternetAddress(sendIp),
          sendPort,
        );

        setState(() {
          _lastGpsData = "LÄHETETTY:\n$humanReadable\n\nNMEA:\n$nmea";
          _packetCount++;
        });
      } catch (e) {
        print("Lähetysvirhe: $e");
      }
    } else {
      // Näytetään data vaikka ei lähetetäkään
      setState(() {
        _lastGpsData = humanReadable + "\n\nNMEA:\n$nmea";
      });
    }
  }

  String _generateHumanReadable(Position pos) {
    return "Leveysaste: ${pos.latitude.toStringAsFixed(6)}\n"
        "Pituusaste: ${pos.longitude.toStringAsFixed(6)}\n"
        "Korkeus: ${pos.altitude.toStringAsFixed(1)} m\n"
        "Nopeus: ${(pos.speed * 3.6).toStringAsFixed(1)} km/h\n"
        "Suunta: ${pos.heading.toStringAsFixed(1)}°\n"
        "Tarkkuus: ${pos.accuracy.toStringAsFixed(1)} m\n"
        "Aika: ${pos.timestamp}";
  }

  void _toggleStreaming() async {
    if (_isStreaming) {
      _sendSocket?.close();
      _sendSocket = null;
      WakelockPlus.disable();
      setState(() {
        _isStreaming = false;
        _packetCount = 0;
      });
    } else {
      try {
        // Luodaan lähetys-socket
        _sendSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _sendSocket?.broadcastEnabled = true;

        WakelockPlus.enable();

        setState(() {
          _isStreaming = true;
          _packetCount = 0;
        });
      } catch (e) {
        setState(() {
          _lastGpsData = "Verkkovirhe: $e\n\n$_lastGpsData";
        });
      }
    }
  }

  String _generateRMC(Position pos) {
    final now = DateTime.now().toUtc();
    String time =
        "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";
    String date =
        "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString().substring(2)}";

    String formatCoord(double coord, bool isLat) {
      double absCoord = coord.abs();
      int deg = absCoord.toInt();
      double min = (absCoord - deg) * 60;
      String dir = isLat ? (coord >= 0 ? 'N' : 'S') : (coord >= 0 ? 'E' : 'W');
      String degStr = isLat
          ? deg.toString().padLeft(2, '0')
          : deg.toString().padLeft(3, '0');
      return "$degStr${min.toStringAsFixed(4)},$dir";
    }

    // Nopeus solmuiksi ja suunta
    double speedKnots = pos.speed * 1.94384;
    String payload =
        "GPRMC,$time,A,${formatCoord(pos.latitude, true)},${formatCoord(pos.longitude, false)},${speedKnots.toStringAsFixed(1)},${pos.heading.toStringAsFixed(1)},$date,,";

    // Checksumin laskenta
    int checksum = 0;
    for (int i = 0; i < payload.length; i++) {
      checksum ^= payload.codeUnitAt(i);
    }
    return "\$$payload*${checksum.toRadixString(16).toUpperCase().padLeft(2, '0')}\r\n";
  }

  Widget _buildTextField(
      String label, TextEditingController controller, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.blueGrey),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("GPS NMEA Network Streamer"),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lähetys asetukset
            const Text(
              "LÄHETYS ASETUKSET",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _buildTextField(
              "Lähetys IP-osoite",
              _sendIpController,
              !_isStreaming,
            ),
            _buildTextField(
              "Lähetys portti",
              _sendPortController,
              !_isStreaming,
            ),
            const SizedBox(height: 30),

            // Status
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "GPS: ${_gpsActive ? 'AKTIIVINEN' : 'EI AKTIIVINEN'}",
                    style: TextStyle(
                      color: _gpsActive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Striimaus: ${_isStreaming ? 'KÄYNNISSÄ' : 'PYSÄYTETTY'}",
                    style: TextStyle(
                      color: _isStreaming ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Paketteja lähetetty: $_packetCount",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // GPS data
            const Text(
              "GPS DATA:",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.all(15),
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _lastGpsData,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Aloita/Pysäytä nappi
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isStreaming ? Colors.red : Colors.green,
                minimumSize: const Size(200, 60),
              ),
              onPressed: _toggleStreaming,
              child: Text(
                _isStreaming ? "PYSÄYTÄ VERKKOLÄHETYS" : "ALOITA VERKKOLÄHETYS",
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
