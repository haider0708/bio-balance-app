import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/repositories/ticket_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/operation_helpers.dart';
import '../workspace/workspace_view_model.dart';

/// The delivery ticket (bon de livraison) and the QR to stick on the parcel.
/// Only the shipper sees it: the receiving store scans the parcel instead.
class DeliveryTicketScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final String deliveryId;
  // A grossiste names its depot; BioBalance omits it.
  final Store? depot;
  const DeliveryTicketScreen({
    super.key,
    required this.vm,
    required this.deliveryId,
    this.depot,
  });
  @override
  State<DeliveryTicketScreen> createState() => _DeliveryTicketScreenState();
}

class _DeliveryTicketScreenState extends State<DeliveryTicketScreen> {
  late final repository = TicketRepository(widget.vm.repositoryContext);
  final label = GlobalKey();
  Json? ticket;
  String? error;
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await repository.get(
        widget.deliveryId,
        depot: widget.depot,
      );
      if (mounted) {
        setState(() {
          ticket = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> share() async {
    final boundary =
        label.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || busy) return;
    setState(() => busy = true);
    await run(context, () async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const AppFailure('SHARE_FAILED', 'Étiquette indisponible.');
      }
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${ticket!['number']}.png');
      await file.writeAsBytes(Uint8List.view(data.buffer), flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          title: 'Bon de livraison ${ticket!['number']}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    });
    if (mounted) setState(() => busy = false);
  }

  /// A lost or damaged label: the old QR stops working, the number stays.
  Future<void> renew() async {
    final current = ticket!;
    if (!await confirmAction(
      context,
      'Renouveler le QR ?',
      'L’ancien QR ne sera plus accepté. Collez le nouveau sur le colis.',
      label: 'Renouveler',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    await run(context, () async {
      await widget.vm.online(
        {'type': 'delivery.reissue', 'deliveryId': widget.deliveryId},
        expectedVersion: integer(current['deliveryVersion']),
        targetStore: Store.fromJson({
          'id': current['storeId'],
          'organizationId': current['organizationId'],
          'name': current['storeName'],
          'organizationName': current['groupName'],
          'permissions': ['manage'],
        }),
        supplierStoreId: widget.depot?.id,
      );
      await load();
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    return Scaffold(
      appBar: AppBar(title: const Text('Bon de livraison')),
      body: Content(
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) Notice(error!, retry: load),
          if (t != null) ...[
            Center(
              child: RepaintBoundary(
                key: label,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: t['qr'],
                        size: 240,
                        backgroundColor: Colors.white,
                        semanticsLabel: 'QR du bon ${t['number']}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t['number'],
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        t['storeName'],
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Collez ce QR sur le colis. Le responsable du magasin le scanne à la réception pour ajouter les quantités à son stock. Il ne le voit pas dans son application.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : share,
                  icon: const Icon(AppIcons.share),
                  label: const Text('Partager ou imprimer'),
                ),
                if (t['status'] == 'dispatched')
                  OutlinedButton.icon(
                    onPressed: busy ? null : renew,
                    icon: const Icon(AppIcons.refresh),
                    label: const Text('Renouveler le QR'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SectionTitle(
              'Contenu du colis',
              subtitle:
                  '${t['groupName']} · ${t['storeName']}\nExpédié le ${TunisDates.timestampLabel(t['dispatchedAt'])}',
            ),
            for (final line in objects(t['lines']))
              CompactRow(
                title: widget.vm.productName(line['productId']),
                value: '${line['quantity']} u.',
                subtitle: [
                  for (final a in objects(line['allocations']))
                    'Lot ${a['batch']} · exp. ${TunisDates.dateOnlyLabel(a['expiry'])} × ${a['quantity']}',
                  if (line['unitPriceMillimes'] != null)
                    'Prix : ${Money(integer(line['unitPriceMillimes'])).formatted} l’unité',
                ].join('\n'),
                icon: AppIcons.package,
              ),
            if (t['totalMillimes'] != null)
              CompactRow(
                title: 'Valeur du bon',
                value: Money(integer(t['totalMillimes'])).formatted,
                icon: AppIcons.receiptLongOutlined,
              ),
          ],
        ],
      ),
    );
  }
}
