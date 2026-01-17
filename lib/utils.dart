import 'dart:io';
import 'package:path_provider/path_provider.dart';

const String tagLeaders = '!@#^&~+=\\|';

Future<File> getFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/bunyan.csv');
}
