// Copyright (c) 2016 P.Y. Laligand

import 'dart:io' show Platform;
import 'dart:async' show runZoned;

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_route/shelf_route.dart';
import 'package:timezone/standalone.dart';

import '../lib/auth_handler.dart';
import '../lib/bungie_middleware.dart';
import '../lib/card_handler.dart';
import '../lib/grimoire_handler.dart';
import '../lib/handlers/actions_handler.dart';
import '../lib/handlers/profile_handler.dart';
import '../lib/lfg_handler.dart';
import '../lib/online_handler.dart';
import '../lib/slack_client_middleware.dart';
import '../lib/slack_verification_middleware.dart';
import '../lib/the_hundred_middleware.dart';
import '../lib/trials_handler.dart';
import '../lib/triumphs_handler.dart';
import '../lib/twitch_handler.dart';
import '../lib/wasted_handler.dart';
import '../lib/weekly_handler.dart';
import '../lib/xur_handler.dart';

/// Returns the value for [name] in the server configuration.
String _getConfigValue(String name) {
  final value = Platform.environment[name];
  if (value == null) {
    throw 'Missing configuration value for $name';
  }
  return value;
}

main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.loggerName}: ${rec.message}');
  });

  await initializeTimeZone();

  final log = new Logger('DestinySlackBot');
  final portEnv = Platform.environment['PORT'];
  final port = portEnv == null ? 9999 : int.parse(portEnv);

  final slackTokens = _getConfigValue('SLACK_VALIDATION_TOKENS').split(',');
  final bungieApiKey = _getConfigValue('BUNGIE_API_KEY');
  final bungieClanId = _getConfigValue('BUNGIE_CLAN_ID');
  final worldDatabase = _getConfigValue('DATABASE_URL');
  final useDelayedResponses =
      _getConfigValue('USE_DELAYED_RESPONSES') == 'true';
  final twitchClientId = _getConfigValue('TWITCH_CLIENT_ID');
  final twitchStreamers = _getConfigValue('TWITCH_STREAMERS').split(',');
  final theHundredAuthToken = _getConfigValue('THE_HUNDRED_AUTH_TOKEN');
  final theHundredGroupId = _getConfigValue('THE_HUNDRED_GROUP_ID');
  final slackAuthToken = _getConfigValue('SLACK_BOT_TOKEN');
  final slackClientId = _getConfigValue('SLACK_CLIENT_ID');
  final slackClientSecret = _getConfigValue('SLACK_CLIENT_SECRET');
  final slackVerificationToken = _getConfigValue('SLACK_VERIFICATION_TOKEN');

  final baseMiddleware = const shelf.Pipeline()
      .addMiddleware(
          shelf.logRequests(logger: (String message, _) => log.info(message)))
      .addMiddleware(
          TheHundredMiddleWare.get(theHundredAuthToken, theHundredGroupId))
      .addMiddleware(SlackClientMiddleware.get(slackAuthToken))
      .middleware;

  final commandMiddleware = const shelf.Pipeline()
      .addMiddleware(BungieMiddleWare.get(bungieApiKey, worldDatabase))
      .addMiddleware(
          SlackVerificationMiddleware.get(slackTokens, useDelayedResponses))
      .middleware;

  final rootRouter = router()
    ..addAll(
        (Router r) => r
          ..get('/',
              (_) => new shelf.Response.ok('This is the Destiny Slack app!'))
          ..addAll(new AuthHandler(slackClientId, slackClientSecret),
              path: '/auth')
          ..addAll(new ActionsHandler(slackVerificationToken), path: '/actions')
          ..addAll(
              (Router r) => r
                ..addAll(new TrialsHandler(), path: '/trials')
                ..addAll(new OnlineHandler(bungieClanId), path: '/online')
                ..addAll(new GrimoireHandler(), path: '/grimoire')
                ..addAll(new CardHandler(), path: '/card')
                ..addAll(new XurHandler(), path: '/xur')
                ..addAll(new TwitchHandler(twitchClientId, twitchStreamers),
                    path: '/twitch')
                ..addAll(new WeeklyHandler(), path: '/weekly')
                ..addAll(new TriumphsHandler(), path: '/triumphs')
                ..addAll(new LfgHandler(), path: '/lfg')
                ..addAll(new WastedHandler(), path: '/wasted')
                ..addAll(new ProfileHandler(), path: '/profile'),
              path: '/commands',
              middleware: commandMiddleware),
        middleware: baseMiddleware);

  runZoned(() {
    log.info('Serving on port $port');
    printRoutes(rootRouter, printer: log.info);
    io.serve(rootRouter.handler, '0.0.0.0', port);
  }, onError: (e, stackTrace) => log.severe('Oh noes! $e $stackTrace'));
}
