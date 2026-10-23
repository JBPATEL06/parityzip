class ToolInfo {
  final bool isFound;
  final String? path;
  final String? binaryName;

  const ToolInfo.found(this.path, this.binaryName) : isFound = true;

  const ToolInfo.missing() : isFound = false, path = null, binaryName = null;

  @override
  String toString() => isFound ? 'Found($binaryName at $path)' : 'Missing';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolInfo &&
          runtimeType == other.runtimeType &&
          isFound == other.isFound &&
          path == other.path &&
          binaryName == other.binaryName;

  @override
  int get hashCode => Object.hash(isFound, path, binaryName);
}

class ToolStatus {
  final ToolInfo sevenZip;
  final ToolInfo par2;

  const ToolStatus({required this.sevenZip, required this.par2});

  bool get allFound => sevenZip.isFound && par2.isFound;
  bool get anyMissing => !allFound;

  List<String> get missingTools {
    final missing = <String>[];
    if (!sevenZip.isFound) missing.add('7z');
    if (!par2.isFound) missing.add('par2');
    return missing;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolStatus &&
          runtimeType == other.runtimeType &&
          sevenZip == other.sevenZip &&
          par2 == other.par2;

  @override
  int get hashCode => Object.hash(sevenZip, par2);

  @override
  String toString() => 'ToolStatus(7z: $sevenZip, par2: $par2)';
}
