import 'package:cloud_firestore/cloud_firestore.dart';

class Supplier {
  final String id;
  final String businessId;
  final String name;
  final String phone;
  final double balance; // positive = we owe them

  Supplier({required this.id, required this.businessId, required this.name, required this.phone, required this.balance});

  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Supplier(
      id: doc.id,
      businessId: d['businessId'] ?? '',
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      balance: (d['balance'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId,
    'name': name,
    'phone': phone,
    'balance': balance,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
