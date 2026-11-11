import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';

/// Whether the map draws its street tiles (OpenStreetMap). Off in tests, which have no network:
/// the points and the circle are still drawn.
final mapTilesProvider = Provider<bool>((_) => true);

/// Metres between two points on the earth.
int metersBetween(LatLng a, LatLng b) =>
    const Distance().as(LengthUnit.Meter, a, b).round();

/// Where the phone was when a visit was recorded, on a street map: the recorded point with the
/// circle of its doubt, and the place's own position when it has one.
class PositionMap extends ConsumerWidget {
  const PositionMap({
    required this.recorded,
    this.place,
    this.accuracyMeters,
    super.key,
  });

  final LatLng recorded;
  final LatLng? place;
  final double? accuracyMeters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final both = place != null && place != recorded;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: recorded,
            initialZoom: 17,
            // Both points in view, when there are two.
            initialCameraFit: both
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([recorded, place!]),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 18,
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            if (ref.watch(mapTilesProvider))
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'tn.biobalance.app',
              )
            else
              ColoredBox(color: scheme.surfaceContainerHighest),
            if (accuracyMeters != null && accuracyMeters! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: recorded,
                    radius: accuracyMeters!,
                    useRadiusInMeter: true,
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderColor: scheme.primary.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            if (both)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [recorded, place!],
                    color: context.status.muted,
                    strokeWidth: 2,
                    pattern: const StrokePattern.dotted(),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (place != null)
                  Marker(
                    point: place!,
                    width: 36,
                    height: 36,
                    child: _Pin(
                      icon: LucideIcons.store,
                      color: context.status.muted,
                    ),
                  ),
                Marker(
                  point: recorded,
                  width: 36,
                  height: 36,
                  child: _Pin(icon: LucideIcons.user, color: scheme.primary),
                ),
              ],
            ),
            // The map's makers are named, as their licence asks.
            Align(
              alignment: AlignmentDirectional.bottomEnd,
              child: Container(
                color: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: const Text(
                  '© OpenStreetMap',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
    ),
    child: Icon(icon, size: 18, color: Colors.white),
  );
}
