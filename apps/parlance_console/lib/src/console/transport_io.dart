import 'dart:convert';
import 'dart:io';

import 'client.dart';

ConsoleClient? connectWindow() {
  if (Platform.environment['PARLANCE_CONSOLE_STDIO'] != '1') return null;
  return ConsoleClient(
    utf8.decoder.bind(stdin).transform(const LineSplitter()),
    stdout,
  );
}
