import 'package:cloud_firestore/cloud_firestore.dart';

/// A credit customer (உதிரி) of the shop.
///
/// [balance] is the running amount the customer OWES the shop:
///   balance > 0  → money the shop still has to collect
///   balance <= 0 → fully settled (or shop owes the customer, e.g. advance)
/// It is kept atomically in sync with every credit/payment entry, exactly
/// like [Supplier.balance] but with the sign meaning flipped to the shop's
/// favour.
class Customer {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final double balance;
  final String shopId; // '' = visible across all shops; 'sX' = this shop only

  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.balance,
    this.shopId = '',
  });

  factory Customer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Customer(
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

  Customer copyWith({
    String? id,
    String? businessId,
    String? name,
    String? phone,
    double? balance,
    String? shopId,
  }) => Customer(
    id:         id         ?? this.id,
    businessId: businessId ?? this.businessId,
    name:       name       ?? this.name,
    phone:      phone      ?? this.phone,
    balance:    balance    ?? this.balance,
    shopId:     shopId     ?? this.shopId,
  );
}
