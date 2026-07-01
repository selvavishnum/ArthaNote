/// Common construction materials with HSN codes, default units and indicative
/// rates (₹). Used by the Material entry picker; the actual rate is pre-filled
/// from the builder's own recent prices when available (see ConstructionService
/// recentRate), falling back to these defaults — editable per area.
class ConstructionMaterial {
  final String name;
  final String hsn;
  final String unit;
  final double rate; // indicative default
  const ConstructionMaterial(this.name, this.hsn, this.unit, this.rate);
}

const List<ConstructionMaterial> kConstructionMaterials = [
  ConstructionMaterial('Cement (OPC 43)', '2523', 'bag', 400),
  ConstructionMaterial('Cement (OPC 53)', '2523', 'bag', 420),
  ConstructionMaterial('Cement (PPC)', '2523', 'bag', 380),
  ConstructionMaterial('TMT Steel Bar', '7214', 'kg', 62),
  ConstructionMaterial('Binding Wire', '7217', 'kg', 80),
  ConstructionMaterial('River Sand', '2505', 'unit', 6000),
  ConstructionMaterial('M-Sand', '2505', 'unit', 4500),
  ConstructionMaterial('P-Sand (Plastering)', '2505', 'unit', 5000),
  ConstructionMaterial('Blue Metal / Jelly (20mm)', '2517', 'unit', 5500),
  ConstructionMaterial('Blue Metal / Jelly (12mm)', '2517', 'unit', 5800),
  ConstructionMaterial('Gravel', '2517', 'unit', 4000),
  ConstructionMaterial('Red Bricks', '6904', '1000 nos', 8000),
  ConstructionMaterial('Cement Blocks (4")', '6810', 'nos', 32),
  ConstructionMaterial('Cement Blocks (6")', '6810', 'nos', 42),
  ConstructionMaterial('AAC Blocks', '6810', 'nos', 55),
  ConstructionMaterial('RMC (Ready Mix Concrete)', '3824', 'm³', 5500),
  ConstructionMaterial('Wall Putty', '3214', 'bag', 900),
  ConstructionMaterial('Primer', '3209', 'litre', 180),
  ConstructionMaterial('Emulsion Paint', '3209', 'litre', 260),
  ConstructionMaterial('Enamel Paint', '3208', 'litre', 300),
  ConstructionMaterial('Floor Tiles', '6907', 'box', 450),
  ConstructionMaterial('Wall Tiles', '6907', 'box', 400),
  ConstructionMaterial('Granite', '6802', 'sqft', 120),
  ConstructionMaterial('Marble', '6802', 'sqft', 150),
  ConstructionMaterial('PVC Pipe', '3917', 'nos', 350),
  ConstructionMaterial('CPVC Pipe', '3917', 'nos', 420),
  ConstructionMaterial('Electrical Wire', '8544', 'coil', 2200),
  ConstructionMaterial('Switch / Socket', '8536', 'nos', 120),
  ConstructionMaterial('Plywood', '4412', 'sheet', 1800),
  ConstructionMaterial('Water Tank', '3925', 'nos', 6500),
  ConstructionMaterial('Waterproofing Compound', '3824', 'litre', 250),
  ConstructionMaterial('White Cement', '2523', 'kg', 40),
];
