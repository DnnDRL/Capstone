// main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

const String googleApiKey = 'AIzaSyCA2yxUxy3azVahnOnHPMEFs4IaRUOwez8';

void main() => runApp(FireAlarmApp());

class FireAlarmApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fire Alarm Monitoring',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF101010),
        colorScheme: ColorScheme.dark(primary: Colors.greenAccent.shade400),
      ),
      home: FireAlarmHome(),
    );
  }
}

class FireAlarmHome extends StatefulWidget {
  @override
  _FireAlarmHomeState createState() => _FireAlarmHomeState();
}

class _FireAlarmHomeState extends State<FireAlarmHome>
    with SingleTickerProviderStateMixin {
  Timer? timer;
  Map<String, dynamic>? sensorData;
  late TabController _tabController;
  GoogleMapController? mapController;

  final String espUrl = 'http://192.168.100.235/data';

  LatLng? location;
  double simBalance = 0.0;
  String simBalanceRaw = "Unknown";
  bool isLoading = false;
  bool mapReady = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchData();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => fetchData());
  }

  @override
  void dispose() {
    timer?.cancel();
    _tabController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  Future<void> fetchData() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    try {
      const username = 'admin';
      const password = 'ESP23pass';
      final basicAuth =
          'Basic ' + base64Encode(utf8.encode('$username:$password'));

      final response = await http
          .get(
            Uri.parse(espUrl),
            headers: {
              'Authorization': basicAuth,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        double? lat;
        double? lng;

        if (data['latitude'] != null) {
          lat = (data['latitude'] is num)
              ? data['latitude'].toDouble()
              : double.tryParse(data['latitude'].toString());
        }
        if (data['longitude'] != null) {
          lng = (data['longitude'] is num)
              ? data['longitude'].toDouble()
              : double.tryParse(data['longitude'].toString());
        }

        setState(() {
          sensorData = Map<String, dynamic>.from(data);
          if (lat != null && lng != null) {
            location = LatLng(lat, lng);
            _moveMapCameraTo(location!);
          }
          final simRaw = (data['sim_credit'] ?? 'Unknown').toString();
          simBalanceRaw = simRaw;
          final numeric = RegExp(r'(\d+(\.\d+)?)').firstMatch(simRaw);
          if (numeric != null) {
            simBalance = double.tryParse(numeric.group(0)!) ?? simBalance;
          }
        });
      } else {
        debugPrint('ESP returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _moveMapCameraTo(LatLng target) async {
    if (mapController == null) return;
    try {
      await mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final temperature = (sensorData?['temperature'] ?? 0.0).toDouble();
    final humidity = (sensorData?['humidity'] ?? 0.0).toDouble();
    final flameStr = (sensorData?['flame'] ?? '').toString().toUpperCase();
    final smokeStr = (sensorData?['smoke'] ?? '').toString().toUpperCase();
    final flame = flameStr.contains('DETECT') ? 100.0 : 0.0;
    final smoke = smokeStr.contains('DETECT') ? 100.0 : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.greenAccent.shade700,
        title: const Text('Fire Alarm Monitoring',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.greenAccent.shade200,
          tabs: const [
            Tab(icon: Icon(Icons.sensors), text: 'Monitoring'),
            Tab(icon: Icon(Icons.map), text: 'Map'),
            Tab(icon: Icon(Icons.sim_card), text: 'Sim Credit'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _withFooter(_buildMonitoringTab(temperature, humidity, flame, smoke)),
          _withFooter(_buildMapTab()),
          _withFooter(_buildSimCreditTab()),
        ],
      ),
    );
  }

  Widget _withFooter(Widget child) {
    return Column(
      children: [
        Expanded(child: child),
        Container(
          color: const Color(0xFF181818),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          alignment: Alignment.center,
          child: Column(
            children: const [
              Text('For more information and contact us:',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
              SizedBox(height: 4),
              Text('firealarmmonitor@gmail.com',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonitoringTab(
      double temp, double humid, double flame, double smoke) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Wrap(
          spacing: 20,
          runSpacing: 20,
          alignment: WrapAlignment.center,
          children: [
            _buildGaugeCard('TEMPERATURE', temp, '°C', Colors.blueAccent),
            _buildGaugeCard('HUMIDITY', humid, '%', Colors.cyanAccent),
            _buildGaugeCard('FLAME', flame, '', Colors.redAccent),
            _buildGaugeCard('SMOKE', smoke, '', Colors.orangeAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildGaugeCard(String title, double value, String unit, Color color) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 10),
            SizedBox(
              width: 120,
              height: 120,
              child: SfRadialGauge(axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 100,
                  showLabels: false,
                  showTicks: false,
                  axisLineStyle: AxisLineStyle(
                    thickness: 0.2,
                    thicknessUnit: GaugeSizeUnit.factor,
                    color: Colors.grey.shade800,
                  ),
                  pointers: <GaugePointer>[
                    RangePointer(
                      value: value.clamp(0.0, 100.0),
                      color: color,
                      width: 0.2,
                      sizeUnit: GaugeSizeUnit.factor,
                      cornerStyle: CornerStyle.bothCurve,
                    ),
                  ],
                  annotations: <GaugeAnnotation>[
                    GaugeAnnotation(
                      widget: Text(
                        unit.isNotEmpty
                            ? '${value.toStringAsFixed(1)} $unit'
                            : (value == 100 ? "DETECTED" : "SAFE"),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      positionFactor: 0.1,
                      angle: 90,
                    )
                  ],
                )
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapTab() {
    if (location == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.greenAccent),
            SizedBox(height: 20),
            Text('Waiting for GPS data...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final marker = Marker(
      markerId: const MarkerId('fire_location'),
      position: location!,
      infoWindow: const InfoWindow(title: 'Device Location'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: location!, zoom: 16),
      markers: {marker},
      onMapCreated: (controller) {
        mapController = controller;
        mapReady = true;
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
    );
  }

  Widget _buildSimCreditTab() {
    final simNumber = (sensorData?['sim_number'] ?? 'Unknown').toString();
    final simProvider = (sensorData?['sim_provider'] ?? 'Unknown').toString();

    return Center(
      child: Card(
        color: const Color(0xFF1E1E1E),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.all(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sim Credit Balance',
                  style: TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 15),
              Text(
                simBalanceRaw.toLowerCase() != 'unknown'
                    ? '₱ ${simBalance.toStringAsFixed(2)}'
                    : simBalanceRaw,
                style: const TextStyle(
                    fontSize: 36, fontWeight: FontWeight.bold, color: Colors.greenAccent),
              ),
              const SizedBox(height: 10),
              Text('SIM Number: $simNumber',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 5),
              Text('Provider: $simProvider',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 15),
              const Text(
                '⚠️ Restart the app after topping up to view your new balance.',
                style: TextStyle(color: Colors.yellowAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
