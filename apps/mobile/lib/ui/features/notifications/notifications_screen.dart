import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class NotificationsScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const NotificationsScreen({super.key, required this.vm});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Json> items = [];
  String? error;
  bool loading = true, fetching = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    try {
      final result = objects(await widget.vm.inbox.list());
      if (mounted) {
        setState(() {
          items = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      fetching = false;
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: Content(
      maxWidth: 760,
      children: [
        if (error != null) Notice(error!, retry: load),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (!loading && items.isEmpty)
          const EmptyState(
            title: 'Aucune notification',
            description:
                'Les informations utiles à votre activité apparaîtront ici.',
            icon: Icons.notifications_none,
          ),
        ...items.map(
          (n) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Icon(
                  n['readAt'] == null
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none,
                  color: darkGreen,
                ),
                title: Text(n['title']),
                subtitle: Text(n['body']),
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
                            '${widget.vm.state.store?.name ?? 'BioBalance'}\n\n${message['body']}',
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
                    await load();
                  } catch (e) {
                    if (mounted) {
                      setState(() => error = SessionViewModel.message(e));
                    }
                  }
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
