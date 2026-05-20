class Shop {
  final String id;
  final String name;
  final String icon;
  final String type;

  const Shop({required this.id, required this.name, required this.icon, required this.type});

  factory Shop.fromMap(String id, Map<String, dynamic> m) =>
      Shop(id: id, name: m['name'] ?? '', icon: m['icon'] ?? '🏪', type: m['type'] ?? 'other');

  Map<String, dynamic> toMap() => {'name': name, 'icon': icon, 'type': type};
}

const kShopTypes = [
  {'type': 'vegetables',  'icon': '🥬', 'label': 'Vegetables'},
  {'type': 'grocery',     'icon': '🛒', 'label': 'Grocery'},
  {'type': 'tea',         'icon': '☕', 'label': 'Tea Shop'},
  {'type': 'bakery',      'icon': '🥐', 'label': 'Bakery'},
  {'type': 'textile',     'icon': '👗', 'label': 'Textile'},
  {'type': 'hardware',    'icon': '🔧', 'label': 'Hardware'},
  {'type': 'jewellery',   'icon': '💍', 'label': 'Jewellery'},
  {'type': 'medical',     'icon': '💊', 'label': 'Medical'},
  {'type': 'hotel',       'icon': '🍽️', 'label': 'Hotel'},
  {'type': 'finance',     'icon': '💰', 'label': 'Finance'},
  {'type': 'chit',        'icon': '🤝', 'label': 'Chit Fund'},
  {'type': 'other',       'icon': '🏪', 'label': 'Other'},
];
