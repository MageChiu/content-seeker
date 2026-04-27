class DownloadRequest {
  final String mediaId;
  final String sourceId;
  final Uri url;
  final String filename;
  final Map<String, String> headers;

  const DownloadRequest({
    required this.mediaId,
    required this.sourceId,
    required this.url,
    required this.filename,
    this.headers = const {},
  });
}
