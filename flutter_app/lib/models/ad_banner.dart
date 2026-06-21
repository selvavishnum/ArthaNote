import 'package:cloud_firestore/cloud_firestore.dart';

/// A premium ad created by the app admin and shown to non-admin users
/// on the Reports tab when they return to the app from background.
class AdBanner {
  final String id;
  final String title;
  final String description;
  final String imageUrl;   // optional — empty string = text-only ad
  final String linkUrl;    // optional — tapping the ad opens this URL
  final String ctaText;    // button label, defaults to "Learn More"
  final bool   active;
  final DateTime createdAt;

  const AdBanner({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.linkUrl,
    required this.ctaText,
    required this.active,
    required this.createdAt,
  });

  factory AdBanner.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AdBanner(
      id:          doc.id,
      title:       d['title']       as String? ?? '',
      description: d['description'] as String? ?? '',
      imageUrl:    d['imageUrl']    as String? ?? '',
      linkUrl:     d['linkUrl']     as String? ?? '',
      ctaText:     d['ctaText']     as String? ?? 'Learn More',
      active:      d['active']      as bool?   ?? true,
      createdAt:   (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'title':       title,
    'description': description,
    'imageUrl':    imageUrl,
    'linkUrl':     linkUrl,
    'ctaText':     ctaText,
    'active':      active,
    'createdAt':   FieldValue.serverTimestamp(),
  };
}
