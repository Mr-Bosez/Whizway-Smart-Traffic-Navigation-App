import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:math' as Math;


class OpenStreetMap extends StatefulWidget {
  const OpenStreetMap({super.key});
  @override
  State<OpenStreetMap> createState() => _OpenStreetMapState();
}

class _OpenStreetMapState extends State<OpenStreetMap> {

  final mapController = MapController();
  final locationService = Location();
  final searchController = TextEditingController();
  IO.Socket? socket;

  LatLng? currentLoc;
  LatLng? destination;
  List<LatLng> routePoints = [];
  List<LatLng> alternativeRoutePoints = [];
  List<Marker> cameraMarkers = [];

  @override
  void initState() {
    super.initState();
    initLocation();
    fetchCameras();
    setupSocket();
  }

  Future<void> initLocation() async {
    if (!await checkPermissions()) return;
    locationService.onLocationChanged.listen((data) {
      setState(() {
        currentLoc = LatLng(data.latitude!, data.longitude!);
      });
    });
  }

  Future<bool> checkPermissions() async {
    bool enabled = await locationService.serviceEnabled();
    if (!enabled) enabled = await locationService.requestService();
    if (!enabled) return false;

    PermissionStatus status = await locationService.hasPermission();
    if (status == PermissionStatus.denied) {
      status = await locationService.requestPermission();
      if (status != PermissionStatus.granted) return false;
    }
    return true;
  }

  void setupSocket() {
    socket = IO.io("https://traffic-server-f1fs.onrender.com", {
      "transports": ["websocket"],
      "autoConnect": true,
    });

    socket!.on("connect", (_) => print("🔌 Connected to WebSocket"));
    socket!.on("traffic_update", (data) {
      print("🚦 Socket Data: $data");
      if (data is Map<String, dynamic>) {
        updateCamera(data);
        if (data['traffic'] == 'high' && destination != null && currentLoc != null) {
          LatLng trafficCam = LatLng(data['latitude'], data['longitude']);
          bool onRoute = routePoints.any((point) =>
          Distance().as(LengthUnit.Meter, point, trafficCam) < 30);

          if (onRoute) {
            print("🚧 Traffic detected ahead. Re-routing from user location...");
            fetchAlternativeRoute(currentLoc!, trafficCam);
            return;
          }

        }
      }
    });
  }

  void updateCamera(dynamic data) {
    LatLng pos = LatLng(data['latitude'], data['longitude']);
    Color color = data['traffic'] == 'high' ? Colors.red : Colors.green;

    setState(() {
      cameraMarkers.removeWhere((m) => m.point == pos);
      cameraMarkers.add(Marker(
        point: pos,
        width: 40,
        height: 40,
        child: Icon(Icons.videocam, color: color, size: 35),
      ));
    });
  }

  Future<void> fetchCameras() async {
    final res = await http.get(Uri.parse("https://traffic-server-f1fs.onrender.com/traffic_status"));
    final data = json.decode(res.body);
    for (var cam in data) {
      updateCamera(cam);
    }
    fetchRoute();
  }

  Future<void> fetchRoute() async {
    if (currentLoc == null || destination == null) return;

    final url = Uri.parse(
        "http://router.project-osrm.org/route/v1/driving/${currentLoc!.longitude},${currentLoc!.latitude};${destination!.longitude},${destination!.latitude}?overview=full&geometries=polyline");

    final res = await http.get(url, headers: {
      'User-Agent': 'FlutterTrafficApp/1.0'
    });

    if (res.statusCode == 200) {
      final route = json.decode(res.body);
      final points = PolylinePoints().decodePolyline(route['routes'][0]['geometry']);
      setState(() {
        routePoints = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
        alternativeRoutePoints.clear();
      });
    }
  }



  Future<void> fetchAlternativeRoute(LatLng startPoint, LatLng trafficCam) async {
    if (destination == null) return;

    double radius = 0.003; // Start with ~300m
    const double maxRadius = 0.006; // Max ~600m
    const int pointsCount = 16; // More candidate points
    const double minDetourDistance = 100; // 100 meters minimum from camera

    List<LatLng> detourCandidates = [];

    // Generate detour points around the traffic camera
    for (int i = 0; i < pointsCount; i++) {
      double angle = (2 * Math.pi / pointsCount) * i;
      double lat = trafficCam.latitude + radius * Math.sin(angle);
      double lon = trafficCam.longitude + radius * Math.cos(angle);
      LatLng detourPoint = LatLng(lat, lon);

      // Keep only points at least 100m away from the camera
      double distanceFromCamera = Distance().as(LengthUnit.Meter, detourPoint, trafficCam);
      if (distanceFromCamera > minDetourDistance) {
        detourCandidates.add(detourPoint);
      }
    }

    double shortestDistance = double.infinity;
    List<LatLng> bestRoute = [];

    for (LatLng detourPoint in detourCandidates) {
      final url = Uri.parse(
          "http://router.project-osrm.org/route/v1/driving/"
              "${startPoint.longitude},${startPoint.latitude};"
              "${detourPoint.longitude},${detourPoint.latitude};"
              "${destination!.longitude},${destination!.latitude}"
              "?overview=full&geometries=polyline"
      );

      final res = await http.get(url, headers: {
        'User-Agent': 'FlutterTrafficApp/1.0'
      });

      if (res.statusCode == 200) {
        final route = json.decode(res.body);
        if (route['routes'] != null && route['routes'].isNotEmpty) {
          final geometry = route['routes'][0]['geometry'];
          final points = PolylinePoints().decodePolyline(geometry);
          final routePoints = points.map((p) => LatLng(p.latitude, p.longitude)).toList();
          final distance = route['routes'][0]['distance'];

          // Check if route passes too close to the traffic camera — skip if too close
          bool crossesCamera = routePoints.any(
                (p) => Distance().as(LengthUnit.Meter, p, trafficCam) < 30,
          );
          if (!crossesCamera && distance < shortestDistance) {
            shortestDistance = distance;
            bestRoute = routePoints;
          }
        }
      }
    }

    // If no route was found, try increasing the radius once
    if (bestRoute.isEmpty && radius < maxRadius) {
      radius += 0.0015; // increase by ~150m
      return fetchAlternativeRoute(startPoint, trafficCam); // Retry with a bigger radius
    }

    if (bestRoute.isNotEmpty) {
      setState(() {
        alternativeRoutePoints = bestRoute;
        routePoints.clear(); // Hide the default route
      });
      print("🟣 Best auto-detour route selected with ${bestRoute.length} points");
    } else {
      print("⚠️ No suitable alternative route found.");
    }
  }




  Future<void> searchLocation(String name) async {
    final url = Uri.parse("https://nominatim.openstreetmap.org/search?q=$name&format=json&limit=1");
    try {
      final res = await http.get(url).timeout(Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final newDest = LatLng(lat, lon);

          print("📍 Found destination: $newDest");

          setState(() {
            destination = newDest;
            alternativeRoutePoints.clear();
          });

          mapController.move(newDest, 15);
          await fetchRoute();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content:Text("⚠️ No results found for '$name'",style: TextStyle(color: Colors.white,fontSize: 16),),backgroundColor: Colors.redAccent,)
          );
          print("⚠️ No results found for '$name'");
        }
      }
    } catch (e) {
      print("❌ Error in searchLocation: $e");
    }
  }

  LatLng offsetStart(LatLng loc, [int index = 1]) {
    double offset = 0.0005 * index;
    return LatLng(loc.latitude + offset, loc.longitude + offset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Whizway - Smart Traffic Navigation',style: TextStyle(color: Colors.white,fontSize: 18,fontWeight: FontWeight.bold),),
        leading: Image.asset('assets/images/Whizway2.png'),
        centerTitle: true,
        backgroundColor: Colors.purple,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: currentLoc ?? const LatLng(0, 0),
              initialZoom: 13,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
              CurrentLocationLayer(
                alignPositionOnUpdate: AlignOnUpdate.always,
                alignDirectionOnUpdate: AlignOnUpdate.always,
              ),
              MarkerLayer(markers: cameraMarkers),
              if (destination != null)
                MarkerLayer(markers: [
                  Marker(
                    point: destination!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_pin, color: Colors.red, size: 35),
                  ),
                ]),
              if (routePoints.isNotEmpty && alternativeRoutePoints.isEmpty)
                PolylineLayer(polylines: [
                  Polyline(points: routePoints, color: Colors.blue, strokeWidth: 4),
                ]),
              if (alternativeRoutePoints.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(points: alternativeRoutePoints, color: Colors.orange, strokeWidth: 4),
                ]),
            ],
          ),
          Positioned(
            top: 10,
              left: 10,
              right: 70,
              child:Material(
                elevation: 5,
                shadowColor: Colors.black38,
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                child: TextField(
                  controller: searchController,
                  cursorColor: Colors.purple,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter destination',
                    hintStyle: TextStyle(color: Colors.black38),
                    contentPadding:const EdgeInsets.symmetric(horizontal: 20,vertical: 10),
                  ),
                )
              )
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              onPressed: () {
                if (searchController.text.trim().isNotEmpty) {
                  searchLocation(searchController.text.trim());
                }
              },
              icon: const Icon(Icons.search, color: Colors.purple,size: 30,),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (currentLoc != null) {
            mapController.move(currentLoc!, 15);
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
