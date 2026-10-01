import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';

import 'notifications_view_model.dart';
import '../dashboard/attention_screen.dart';
import '../replenishment/scoped_order_screen.dart';
import '../../core/design.dart';
import '../../core/segment_bar.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class NotificationsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final NotificationsViewModel? model;
  const NotificationsScreen({super.key, required this.vm, this.model});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  late final inbox = widget.model ?? NotificationsViewModel(widget.vm.inbox);
  bool current = false;
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  String? openError;
  String segment = 'all';

  /// Which segment a notification belongs to.
  static String segmentOf(Json n) => switch (n['targetType']) {
    'order' || 'delivery' => 'orders',
    'alert' => 'alerts',
    'reward' || 'claim' => 'rewards',
    _ => 'other',
  };
  List<Json> inSegment(String key) => switch (key) {
    'all' => inbox.items.toList(),
    'unread' => inbox.items.where((n) => n['readAt'] == null).toList(),
    _ => inbox.items.where((n) => segmentOf(n) == key).toList(),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    current = ModalRoute.isCurrentOf(context) ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.model == null) {
        inbox.setActive(current && foreground);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (widget.model == null) inbox.setActive(current && foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.model == null) inbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: inbox,
    builder: (context, _) {
      final shown = inSegment(segment);
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: Content.builder(
          maxWidth: 760,
          onRefresh: () => inbox.load(),
          itemCount: shown.length,
          itemBuilder: (context, index) {
            final n = shown[index];
            final location = widget.vm.state.stores
                .where(
                  (s) =>
                      s.id == n['storeId'] &&
                      s.organizationId == n['organizationId'],
                )
                .firstOrNull;
            final scope = location == null
                ? (n['storeId'] == null
                      ? 'BioBalance'
                      : 'Magasin ${n['storeId'].toString().split('-').first}')
                : '${location.organizationName} · ${location.name}';
            return CompactRow(
              title: n['title'],
              subtitle: '$scope\n${n['body']}',
              icon: n['readAt'] == null
                  ? AppIcons.notificationsActiveOutlined
                  : AppIcons.notificationsNone,
              onTap: () async {
                try {
                  final message = await widget.vm.openNotification(n['id']);
                  if (!context.mounted) return;
                  final store = message['authorizedStore'] != null
                      ? Store.fromJson(
                          Map<String, dynamic>.from(message['authorizedStore']),
                        )
                      : widget.vm.state.stores
                            .where(
                              (s) =>
                                  s.id == message['storeId'] &&
                                  s.organizationId == message['organizationId'],
                            )
                            .firstOrNull;
                  if (store != null &&
                      message['targetType'] == 'order' &&
                      message['targetId'] != null) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExactOrderScreen(
                          parent: widget.vm,
                          store: store,
                          orderId: message['targetId'],
                        ),
                      ),
                    );
                  } else if (store != null &&
                      message['targetType'] == 'alert' &&
                      message['targetId'] != null) {
                    await openExactAlert(context, widget.vm, {
                      ...message,
                      'id': message['targetId'],
                    });
                  } else if (store != null &&
                      message['targetType'] == 'reward' &&
                      message['targetId'] != null) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttentionDetail(
                          parent: widget.vm,
                          store: store,
                          item: {
                            ...message,
                            'id': message['targetId'],
                            'kind': 'rewards',
                          },
                        ),
                      ),
                    );
                  } else {
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(message['title']),
                        content: SingleChildScrollView(
                          child: Text(
                            '${message['groupName'] ?? 'BioBalance'} · ${message['storeName'] ?? ''}\n\n${message['body']}',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Fermer'),
                          ),
                        ],
                      ),
                    );
                  }
                  await inbox.load();
                } catch (e) {
                  if (mounted) {
                    setState(() => openError = SessionViewModel.message(e));
                  }
                }
              },
            );
          },
          children: [
            SegmentBar(
              keyPrefix: 'inbox',
              selected: segment,
              onChanged: (v) => setState(() => segment = v),
              segments: {
                'all': Segment(
                  'Toutes',
                  AppIcons.notificationsNone,
                  inbox.items.length,
                ),
                'unread': Segment(
                  'Non lues',
                  AppIcons.notificationsActiveOutlined,
                  inSegment('unread').length,
                ),
                'alerts': Segment(
                  'Alertes stock',
                  AppIcons.errorOutline,
                  inSegment('alerts').length,
                ),
                'orders': Segment(
                  'Commandes',
                  AppIcons.localShippingOutlined,
                  inSegment('orders').length,
                ),
                'rewards': Segment(
                  'Récompenses',
                  AppIcons.redeemOutlined,
                  inSegment('rewards').length,
                ),
                'other': Segment(
                  'Autres',
                  AppIcons.infoOutline,
                  inSegment('other').length,
                ),
              },
            ),
            const SizedBox(height: 12),
            if (inbox.cached)
              const Notice(
                'Notifications conservées sur ce téléphone. Actualisez pour vérifier leur état.',
              ),
            if (inbox.nextCursor != null)
              TextButton(
                onPressed: inbox.loading ? null : () => inbox.load(more: true),
                child: const Text('Notifications plus anciennes'),
              ),
            TextButton(
              onPressed: () => inbox.load(),
              child: const Text('Actualiser'),
            ),
            if ((openError ?? inbox.error) != null)
              Notice((openError ?? inbox.error)!, retry: inbox.load),
            if (inbox.loading) const Center(child: CircularProgressIndicator()),
            if (!inbox.loading && shown.isEmpty)
              EmptyState(
                title: inbox.items.isEmpty
                    ? 'Aucune notification'
                    : 'Rien dans cette catégorie',
                description: inbox.items.isEmpty
                    ? 'Les informations utiles à votre activité apparaîtront ici.'
                    : 'Choisissez une autre catégorie ci-dessus.',
                icon: AppIcons.notificationsNone,
              ),
          ],
        ),
      );
    },
  );
}
