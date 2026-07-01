class Shop {
  final String id;
  final String name;
  final String icon;
  final String type;

  const Shop({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
  });

  factory Shop.fromMap(String id, Map<String, dynamic> m) => Shop(
    id:   id,
    name: m['name'] as String? ?? '',
    icon: m['icon'] as String? ?? '🏪',
    type: m['type'] as String? ?? 'other',
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'icon': icon,
    'type': type,
  };

  Shop copyWith({String? id, String? name, String? icon, String? type}) => Shop(
    id:   id   ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    type: type ?? this.type,
  );
}

const List<Map<String, String>> kShopTypes = [
  {'type': 'personal',   'icon': '👤', 'label': 'Personal'},
  {'type': 'vegetables', 'icon': '🥬', 'label': 'Vegetables'},
  {'type': 'grocery',    'icon': '🛒', 'label': 'Grocery'},
  {'type': 'tea',        'icon': '☕', 'label': 'Tea Shop'},
  {'type': 'bakery',     'icon': '🥐', 'label': 'Bakery'},
  {'type': 'textile',    'icon': '👗', 'label': 'Textile'},
  {'type': 'hardware',   'icon': '🔧', 'label': 'Hardware'},
  {'type': 'jewellery',  'icon': '💍', 'label': 'Jewellery'},
  {'type': 'medical',    'icon': '💊', 'label': 'Medical'},
  {'type': 'hotel',      'icon': '🍽️', 'label': 'Hotel'},
  {'type': 'finance',    'icon': '💰', 'label': 'Finance'},
  {'type': 'chit',       'icon': '🤝', 'label': 'Chit Fund'},
  {'type': 'construction','icon': '🏗️', 'label': 'Construction'},
  {'type': 'other',      'icon': '🏪', 'label': 'Other'},
];

const Map<String, Map<String, List<String>>> kBizCats = {
  'vegetables': {
    'sales':   ['Cash', 'GPay', 'Card', 'Wholesale', 'Other'],
    'expense': ['Purchase', 'Labour', 'Transport', 'Rent/EB', 'Other'],
  },
  'grocery': {
    'sales':   ['Cash', 'GPay', 'Card', 'Credit', 'Other'],
    'expense': ['Purchase', 'Staff Salary', 'Rent/EB', 'Transport', 'Other'],
  },
  'bakery': {
    'sales':   ['Cash', 'GPay', 'Card', 'Wholesale', 'Other'],
    'expense': ['Raw Material', 'Staff Salary', 'Gas', 'Rent/EB', 'Other'],
  },
  'tea': {
    'sales':   ['Cash', 'GPay', 'Card', 'Other'],
    'expense': ['Milk', 'Sugar', 'Staff Salary', 'Gas', 'Rent/EB', 'Other'],
  },
  'textile': {
    'sales':   ['Cash', 'GPay', 'Card', 'Credit', 'Other'],
    'expense': ['Purchase', 'Staff Salary', 'Rent/EB', 'Alteration', 'Other'],
  },
  'hardware': {
    'sales':   ['Cash', 'GPay', 'Card', 'Credit', 'Other'],
    'expense': ['Purchase', 'Staff Salary', 'Rent/EB', 'Transport', 'Other'],
  },
  'jewellery': {
    'sales':   ['Cash', 'GPay', 'Card', 'Advance', 'Order', 'Other'],
    'expense': ['Material', 'Staff Salary', 'Rent/EB', 'Maintenance', 'Other'],
  },
  'medical': {
    'sales':   ['Cash', 'GPay', 'Card', 'Insurance', 'Other'],
    'expense': ['Purchase', 'Staff Salary', 'Rent/EB', 'Lab Charges', 'Other'],
  },
  'hotel': {
    'sales':   ['Cash', 'GPay', 'Card', 'Parcel', 'Delivery', 'Other'],
    'expense': ['Raw Material', 'Staff Salary', 'Gas', 'Rent/EB', 'Other'],
  },
  'finance': {
    'sales':   ['EMI Collected', 'Interest Income', 'Other'],
    'expense': ['Loan Given', 'Capital Out', 'Expense'],
  },
  'chit': {
    'sales':   ['Monthly Collection', 'Other'],
    'expense': ['Chit Prize', 'Expense', 'Other'],
  },
  'other': {
    'sales':   ['Cash', 'GPay', 'Card', 'Other'],
    'expense': ['Purchase', 'Salary', 'Rent/EB', 'Other'],
  },
};
