import 'package:flutter/material.dart';

import 'notifications_view_model.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class NotificationsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const NotificationsScreen({super.key, required this.vm});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  late final inbox = NotificationsViewModel(widget.vm.inbox);
  bool current = false;
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  String? openError;
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
      if (mounted) inbox.setActive(current && foreground);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    inbox.setActive(current && foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    inbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: inbox,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Content.builder(
        maxWidth: 760,
        itemCount: inbox.items.length,
        itemBuilder: (context, index) {
          final n = inbox.items[index];
          return CompactRow(
            title: n['title'],
            subtitle: n['body'],
            icon: n['readAt'] == null
                ? AppIcons.notificationsActiveOutlined
                : AppIcons.notificationsNone,
            onTap: () async {
              try {
                final message = await widget.vm.openNotification(n['id']);
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(message['title']),
                    content: SingleChildScrollView(
                      child: Text(
                        '${message['storeName'] ?? 'BioBalance'}\n\n${message['body']}',
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
          if ((openError ?? inbox.error) != null)
            Notice((openError ?? inbox.error)!, retry: inbox.load),
          if (inbox.loading) const Center(child: CircularProgressIndicator()),
          if (!inbox.loading && inbox.items.isEmpty)
            const EmptyState(
              title: 'Aucune notification',
              description:
                  'Les informations utiles à votre activité apparaîtront ici.',
              icon: AppIcons.notificationsNone,
            ),
        ],
      ),
    ),
  );
}
