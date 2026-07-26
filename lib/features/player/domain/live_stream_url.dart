import '../../auth/domain/auth_session.dart';
import '../../live_tv/domain/live_channel.dart';

class LiveStreamUrl {
  LiveStreamUrl._();

  static String build({
    required AuthSession session,
    required LiveChannel channel,
  }) {
    final server = session.server.replaceFirst(
      RegExp(r'/+$'),
      '',
    );

    final username = Uri.encodeComponent(
      session.username,
    );

    final password = Uri.encodeComponent(
      session.password,
    );

    return '$server/live/$username/$password/${channel.streamId}.ts';
  }
}