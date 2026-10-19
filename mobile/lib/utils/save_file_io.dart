import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveFile(List<int> bytes, String name, String mimeType) => SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mimeType)],
      fileNameOverrides: [name],
    ));
