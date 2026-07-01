import 'package:cloud_firestore/cloud_firestore.dart';

/// A construction project / site owned by a builder (businessId). Each project
/// has its own ledger of [ConstructionEntry] items. Modelled on ledger7's
/// project concept: budget + client + timeline + status.
class ConstructionProject {
  final String    id;
  final String    businessId;
  final String    name;
  final String    projectType; // residential | commercial | industrial | other
  final String    location;
  final String    mapLink;
  final String    clientName;
  final String    clientPhone;
  final String    status;      // planning | ongoing | onhold | completed
  final double    budget;
  final String    startLabel;  // e.g. "Jun 2026"
  final String    endLabel;    // e.g. "Jun 2027"
  final DateTime? createdAt;

  const ConstructionProject({
    required this.id,
    required this.businessId,
    required this.name,
    this.projectType = 'residential',
    this.location    = '',
    this.mapLink     = '',
    this.clientName  = '',
    this.clientPhone = '',
    this.status      = 'planning',
    this.budget      = 0,
    this.startLabel  = '',
    this.endLabel    = '',
    this.createdAt,
  });

  factory ConstructionProject.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ConstructionProject(
      id:          doc.id,
      businessId:  d['businessId']  as String? ?? '',
      name:        d['name']        as String? ?? '',
      projectType: d['projectType'] as String? ?? 'residential',
      location:    d['location']    as String? ?? '',
      mapLink:     d['mapLink']     as String? ?? '',
      clientName:  d['clientName']  as String? ?? '',
      clientPhone: d['clientPhone'] as String? ?? '',
      status:      d['status']      as String? ?? 'planning',
      budget:      (d['budget']     as num?)?.toDouble() ?? 0,
      startLabel:  d['startLabel']  as String? ?? '',
      endLabel:    d['endLabel']    as String? ?? '',
      createdAt:   d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'businessId':  businessId,
        'name':        name,
        'projectType': projectType,
        'location':    location,
        'mapLink':     mapLink,
        'clientName':  clientName,
        'clientPhone': clientPhone,
        'status':      status,
        'budget':      budget,
        'startLabel':  startLabel,
        'endLabel':    endLabel,
        'createdAt':   createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  ConstructionProject copyWith({
    String? id,
    String? name,
    String? projectType,
    String? location,
    String? mapLink,
    String? clientName,
    String? clientPhone,
    String? status,
    double? budget,
    String? startLabel,
    String? endLabel,
  }) =>
      ConstructionProject(
        id:          id          ?? this.id,
        businessId:  businessId,
        name:        name        ?? this.name,
        projectType: projectType ?? this.projectType,
        location:    location    ?? this.location,
        mapLink:     mapLink     ?? this.mapLink,
        clientName:  clientName  ?? this.clientName,
        clientPhone: clientPhone ?? this.clientPhone,
        status:      status      ?? this.status,
        budget:      budget      ?? this.budget,
        startLabel:  startLabel  ?? this.startLabel,
        endLabel:    endLabel    ?? this.endLabel,
        createdAt:   createdAt,
      );
}
