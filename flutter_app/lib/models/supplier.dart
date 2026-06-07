import 'package:cloud_firestore/cloud_firestore.dart';

class Supplier {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final double balance;
  final String shopId; // '' = visible across all shops; 'sX' = this shop only

  const Supplier({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.balance,
    this.shopId = '',
  });

  factory Supplier.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Supplier(
      id:         doc.id,
      businessId: d['businessId'] as String? ?? '',
      name:       d['name']       as String? ?? '',
      phone:      d['phone']      as String? ?? '',
      balance:    (d['balance']   as num?)?.toDouble() ?? 0,
      shopId:     d['shopId']     as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId,
    'name':       name,
    'phone':      phone,
    'balance':    balance,
    'shopId':     shopId,
    'updatedAt':  FieldValue.serverTimestamp(),
  };

  Supplier copyWith({
    String? id,
    String? businessId,
    String? name,
    String? phone,
    double? balance,
    String? shopId,
  }) => Supplier(
    id:         id         ?? this.id,
    businessId: businessId ?? this.businessId,
    name:       name       ?? this.name,
    phone:      phone      ?? this.phone,
    balance:    balance    ?? this.balance,
    shopId:     shopId     ?? this.shopId,
  );
}
