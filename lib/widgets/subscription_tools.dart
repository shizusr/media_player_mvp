import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

import '../services/app_exception.dart';
import '../services/app_services.dart';
import '../services/subscription_importer.dart';
import 'dialogs.dart';

void _say(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

String _msg(Object e) {
  return e is AppException ? e.message : 'Something went wrong: $e';
}

Future<void> addChannelFlow(BuildContext context, AppServices services) async {
  final messenger = ScaffoldMessenger.of(context);
  final input = await promptText(
    context,
    title: 'Subscribe to a channel',
    label: 'Channel link, @handle or channel id',
  );
  if (input == null || input.trim().isEmpty) return;

  _say(messenger, 'Looking up the channel...');
  try {
    final channel = await services.ytdlp.resolveChannel(input);
    await services.subscriptions.subscribe(channel);
    _say(messenger, 'Subscribed to ${channel.name}');
  } catch (e) {
    _say(messenger, _msg(e));
  }
}

Future<void> importSubscriptionsFlow(
  BuildContext context,
  AppServices services,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'csv', 'db', 'txt', 'opml', 'xml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      _say(messenger, 'Could not read the selected file.');
      return;
    }

    final channels = SubscriptionImporter.parse(utf8.decode(bytes, allowMalformed: true));
    if (channels.isEmpty) {
      _say(messenger, 'No channels were found in this file.');
      return;
    }

    _say(messenger, 'Importing ${channels.length} channels...');
    final added = await services.subscriptions.importChannels(channels);
    _say(
      messenger,
      'Imported $added new ${added == 1 ? 'channel' : 'channels'} '
      '(${channels.length} found in the file).',
    );
  } catch (e) {
    _say(messenger, _msg(e));
  }
}

/// Lists subscribed channels so they can be opened or removed.
Future<void> showChannelsDialog(
  BuildContext context,
  AppServices services,
  void Function(String channelId, String name) onOpen,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Your channels'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ListenableBuilder(
          listenable: services.subscriptions,
          builder: (context, _) {
            final channels = services.subscriptions.channels;
            if (channels.isEmpty) {
              return const Center(child: Text('No subscriptions yet.'));
            }
            return ListView(
              children: [
                for (final c in channels)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(ctx);
                      onOpen(c.channelId, c.name);
                    },
                    trailing: IconButton(
                      tooltip: 'Unsubscribe',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () =>
                          services.subscriptions.unsubscribe(c.channelId),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
