import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStoragePaths {
  const AppStoragePaths();

  Future<Directory> appSupportRoot() async {
    final base = await getApplicationSupportDirectory();
    return _ensureDir(Directory(p.join(base.path, 'content_seeker')));
  }

  Future<Directory> metadataRoot() async {
    final root = await appSupportRoot();
    return _ensureDir(Directory(p.join(root.path, 'metadata')));
  }

  Future<Directory> downloadsRoot() async {
    final root = await appSupportRoot();
    return _ensureDir(Directory(p.join(root.path, 'downloads')));
  }

  Future<Directory> snapshotsRoot() async {
    final root = await appSupportRoot();
    return _ensureDir(Directory(p.join(root.path, 'snapshots')));
  }

  Future<File> metadataFile(String filename) async {
    final metadataDir = await metadataRoot();
    return File(p.join(metadataDir.path, filename));
  }

  Future<Directory> _ensureDir(Directory directory) async {
    if (await directory.exists()) {
      return directory;
    }
    return directory.create(recursive: true);
  }
}
