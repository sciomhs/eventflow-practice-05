class EfUser {
  final String id;
  final String name;
  final String email;
  final String role; // participant | organizer | controller

  const EfUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory EfUser.fromJson(Map<String, dynamic> json) => EfUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
      );
}

class TicketTypeItem {
  final String id;
  final String name;
  final int capacity;
  final int occupied;
  final int remaining;
  final int usedCount;

  const TicketTypeItem({
    required this.id,
    required this.name,
    required this.capacity,
    required this.occupied,
    required this.remaining,
    this.usedCount = 0,
  });

  factory TicketTypeItem.fromJson(Map<String, dynamic> json) => TicketTypeItem(
        id: json['id'] as String,
        name: json['name'] as String,
        capacity: (json['capacity'] as num).toInt(),
        occupied: (json['occupied'] as num?)?.toInt() ?? 0,
        remaining: (json['remaining'] as num?)?.toInt() ?? 0,
        usedCount: (json['used_count'] as num?)?.toInt() ?? 0,
      );
}

class EventItem {
  final String id;
  final String title;
  final String description;
  final String category;
  final String city;
  final String location;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timezone;
  final DateTime registrationClosesAt;
  final DateTime admissionOpensAt;
  final DateTime admissionClosesAt;
  final int capacity;
  final int freeSeats;
  final int usedCount;
  final String status;
  final String? organizerName;
  final List<TicketTypeItem> ticketTypes;

  const EventItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.city,
    required this.location,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    required this.registrationClosesAt,
    required this.admissionOpensAt,
    required this.admissionClosesAt,
    required this.capacity,
    required this.freeSeats,
    this.usedCount = 0,
    required this.status,
    this.organizerName,
    this.ticketTypes = const [],
  });

  factory EventItem.fromJson(Map<String, dynamic> json) => EventItem(
        id: json['id'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        category: (json['category'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        location: json['location'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        timezone: (json['timezone'] as String?) ?? 'UTC',
        registrationClosesAt: json['registration_closes_at'] != null
            ? DateTime.parse(json['registration_closes_at'] as String)
            : DateTime.parse(json['starts_at'] as String),
        admissionOpensAt: DateTime.parse(json['admission_opens_at'] as String),
        admissionClosesAt:
            DateTime.parse(json['admission_closes_at'] as String),
        capacity: (json['capacity'] as num).toInt(),
        freeSeats: (json['free_seats'] as num?)?.toInt() ?? 0,
        usedCount: (json['used_count'] as num?)?.toInt() ?? 0,
        status: json['status'] as String,
        organizerName: json['organizer_name'] as String?,
        ticketTypes: (json['ticket_types'] as List<dynamic>?)
                ?.map((e) => TicketTypeItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

class TicketItem {
  final String id;
  final String eventId;
  final String typeId;
  final String? typeName;
  final String? eventTitle;
  final String? eventLocation;
  final DateTime? eventStartsAt;
  final String? eventTimezone;
  final String? eventStatus;
  final String code;
  final String status; // ISSUED | USED | CANCELLED
  final DateTime? issuedAt;
  final DateTime? cancelledAt;
  final DateTime? usedAt;
  final String? qrToken;

  const TicketItem({
    required this.id,
    required this.eventId,
    required this.typeId,
    this.typeName,
    this.eventTitle,
    this.eventLocation,
    this.eventStartsAt,
    this.eventTimezone,
    this.eventStatus,
    required this.code,
    required this.status,
    this.issuedAt,
    this.cancelledAt,
    this.usedAt,
    this.qrToken,
  });

  factory TicketItem.fromJson(Map<String, dynamic> json) => TicketItem(
        id: json['id'] as String,
        eventId: json['event_id'] as String,
        typeId: json['type_id'] as String,
        typeName: json['type_name'] as String?,
        eventTitle: json['event_title'] as String?,
        eventLocation: json['event_location'] as String?,
        eventStartsAt: json['event_starts_at'] != null
            ? DateTime.parse(json['event_starts_at'] as String)
            : null,
        eventTimezone: json['event_timezone'] as String?,
        eventStatus: json['event_status'] as String?,
        code: json['code'] as String,
        status: json['status'] as String,
        issuedAt: json['issued_at'] != null
            ? DateTime.parse(json['issued_at'] as String)
            : null,
        cancelledAt: json['cancelled_at'] != null
            ? DateTime.parse(json['cancelled_at'] as String)
            : null,
        usedAt: json['used_at'] != null
            ? DateTime.parse(json['used_at'] as String)
            : null,
        qrToken: json['qr_token'] as String?,
      );
}

class CheckInResult {
  final String
      status; // ACCEPTED, ALREADY_USED, WRONG_EVENT, INVALID, CLOSED, SOLD_OUT, CANCELLED, UNCERTAIN
  final bool idempotentReplay;
  final DateTime? serverTime;
  final DateTime? usedAt;
  final String? ticketCode;
  final String? typeName;
  final String? participantName;
  final String message;

  const CheckInResult({
    required this.status,
    required this.idempotentReplay,
    this.serverTime,
    this.usedAt,
    this.ticketCode,
    this.typeName,
    this.participantName,
    required this.message,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) => CheckInResult(
        status: json['status'] as String,
        idempotentReplay: (json['idempotent_replay'] as bool?) ?? false,
        serverTime: json['server_time'] != null
            ? DateTime.parse(json['server_time'] as String)
            : null,
        usedAt: json['used_at'] != null
            ? DateTime.parse(json['used_at'] as String)
            : null,
        ticketCode: json['ticket_code'] as String?,
        typeName: json['type_name'] as String?,
        participantName: json['participant_name'] as String?,
        message: (json['message'] as String?) ?? '',
      );
}

class TimelineBucket {
  final DateTime bucket;
  final int count;

  const TimelineBucket({required this.bucket, required this.count});

  factory TimelineBucket.fromJson(Map<String, dynamic> json) => TimelineBucket(
        bucket: DateTime.parse(json['bucket'] as String),
        count: (json['count'] as num).toInt(),
      );
}

class OrganizerStats {
  final String eventId;
  final String status;
  final int capacity;
  final int issuedCount;
  final int usedCount;
  final int cancelledCount;
  final int freeSeats;
  final int scansTotal;
  final int last24hEntries;
  final List<TicketTypeItem> byType;
  final List<TimelineBucket> timeline;

  const OrganizerStats({
    required this.eventId,
    required this.status,
    required this.capacity,
    required this.issuedCount,
    required this.usedCount,
    required this.cancelledCount,
    required this.freeSeats,
    required this.scansTotal,
    required this.last24hEntries,
    required this.byType,
    this.timeline = const [],
  });

  factory OrganizerStats.fromJson(Map<String, dynamic> json) => OrganizerStats(
        eventId: json['event_id'] as String,
        status: json['status'] as String,
        capacity: (json['capacity'] as num).toInt(),
        issuedCount: (json['issued_count'] as num).toInt(),
        usedCount: (json['used_count'] as num).toInt(),
        cancelledCount: (json['cancelled_count'] as num).toInt(),
        freeSeats: (json['free_seats'] as num).toInt(),
        scansTotal: (json['scans_total'] as num).toInt(),
        last24hEntries: (json['last_24h_entries'] as num).toInt(),
        byType: (json['by_type'] as List<dynamic>)
            .map((e) => TicketTypeItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        timeline: (json['timeline'] as List<dynamic>?)
                ?.map((e) => TimelineBucket.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
