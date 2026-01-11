/// NostrPost model representing a Kind 1 text note
class NostrPost {
  final int kind;
  final String sender;
  final String content;
  final DateTime time;
  final String eventId;

  NostrPost({
    required this.kind,
    required this.sender,
    required this.content,
    required this.time,
    required this.eventId,
  });

  factory NostrPost.fromJson(Map<String, dynamic> json) {
    return NostrPost(
      kind: json['kind'] as int,
      sender: (json['sender'] ?? json['pubkey']) as String,
      content: json['content'] as String,
      time: DateTime.parse(json['time'] as String),
      eventId: json['eventId'] as String? ?? '',
    );
  }
}
