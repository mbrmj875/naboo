class MarketplaceStoreSummary {
  const MarketplaceStoreSummary({
    required this.id,
    required this.name,
    this.tenantUuid,
  });

  final String id;
  final String name;
  final String? tenantUuid;

  bool get isLinked => tenantUuid != null && tenantUuid!.isNotEmpty;

  factory MarketplaceStoreSummary.fromJson(Map<String, dynamic> json) {
    return MarketplaceStoreSummary(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      tenantUuid: json['tenant_uuid']?.toString(),
    );
  }
}

class MarketplaceOrderItem {
  const MarketplaceOrderItem({
    required this.productName,
    required this.quantity,
    required this.unitPriceFils,
    required this.lineTotalFils,
    this.productGlobalId,
  });

  final String? productGlobalId;
  final String productName;
  final num quantity;
  final int unitPriceFils;
  final int lineTotalFils;

  factory MarketplaceOrderItem.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrderItem(
      productGlobalId: json['product_global_id']?.toString(),
      productName: json['product_name']?.toString() ?? '',
      quantity: json['quantity'] as num? ?? 0,
      unitPriceFils: json['unit_price_fils'] as int? ?? 0,
      lineTotalFils: json['line_total_fils'] as int? ?? 0,
    );
  }
}

class MarketplaceOrder {
  const MarketplaceOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentMethod,
    required this.subtotalFils,
    required this.deliveryFeeFils,
    required this.totalFils,
    required this.createdAt,
    this.buyerNotes,
    this.items = const [],
  });

  final String id;
  final String orderNumber;
  final String status;
  final String paymentMethod;
  final int subtotalFils;
  final int deliveryFeeFils;
  final int totalFils;
  final DateTime createdAt;
  final String? buyerNotes;
  final List<MarketplaceOrderItem> items;

  MarketplaceOrder copyWith({List<MarketplaceOrderItem>? items}) {
    return MarketplaceOrder(
      id: id,
      orderNumber: orderNumber,
      status: status,
      paymentMethod: paymentMethod,
      subtotalFils: subtotalFils,
      deliveryFeeFils: deliveryFeeFils,
      totalFils: totalFils,
      createdAt: createdAt,
      buyerNotes: buyerNotes,
      items: items ?? this.items,
    );
  }

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrder(
      id: json['id'].toString(),
      orderNumber: json['order_number'].toString(),
      status: json['status'].toString(),
      paymentMethod: json['payment_method']?.toString() ?? 'cod',
      subtotalFils: json['subtotal_fils'] as int? ?? 0,
      deliveryFeeFils: json['delivery_fee_fils'] as int? ?? 0,
      totalFils: json['total_fils'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'].toString()).toLocal(),
      buyerNotes: json['buyer_notes']?.toString(),
    );
  }
}

abstract final class MarketplaceOrderStatuses {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const readyToShip = 'ready_to_ship';
  static const inTransit = 'in_transit';
  static const atPickupPoint = 'at_pickup_point';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';
}
