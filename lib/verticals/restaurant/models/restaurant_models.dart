/// نماذج مطعم محلية — أعمدة snake_case كما في الـspec.
library;

class RestaurantFloor {
  const RestaurantFloor({
    required this.id,
    required this.tenantId,
    required this.nameAr,
    required this.sortOrder,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final String nameAr;
  final int sortOrder;
  final int? deletedAt;

  factory RestaurantFloor.fromMap(Map<String, Object?> m) => RestaurantFloor(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        nameAr: m['name_ar'] as String,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        deletedAt: m['deleted_at'] as int?,
      );
}

enum DerivedTableState { available, occupied, awaitingPayment }

/// موضع الطاولة بالنسبة للقاعة: وسط أو بمحاذاة جدار.
enum RestaurantTableSeatStyle { center, wall }

enum RestaurantFloorFixtureKind {
  cashier,
  entrance,
  exit,
  bathroom,
  stairs,
  text,
  arrow,
  wall,
  zoneSeating,
  zoneKitchen,
  zoneCashier,
  zoneBathroom,
  hallFrame,
}

extension RestaurantFloorFixtureKindX on RestaurantFloorFixtureKind {
  String get dbValue {
    switch (this) {
      case RestaurantFloorFixtureKind.cashier:
        return 'cashier';
      case RestaurantFloorFixtureKind.entrance:
        return 'entrance';
      case RestaurantFloorFixtureKind.exit:
        return 'exit';
      case RestaurantFloorFixtureKind.bathroom:
        return 'bathroom';
      case RestaurantFloorFixtureKind.stairs:
        return 'stairs';
      case RestaurantFloorFixtureKind.text:
        return 'text';
      case RestaurantFloorFixtureKind.arrow:
        return 'arrow';
      case RestaurantFloorFixtureKind.wall:
        return 'wall';
      case RestaurantFloorFixtureKind.zoneSeating:
        return 'zone_seating';
      case RestaurantFloorFixtureKind.zoneKitchen:
        return 'zone_kitchen';
      case RestaurantFloorFixtureKind.zoneCashier:
        return 'zone_cashier';
      case RestaurantFloorFixtureKind.zoneBathroom:
        return 'zone_bathroom';
      case RestaurantFloorFixtureKind.hallFrame:
        return 'hall_frame';
    }
  }

  String get labelAr {
    switch (this) {
      case RestaurantFloorFixtureKind.cashier:
        return 'كاشير';
      case RestaurantFloorFixtureKind.entrance:
        return 'دخول';
      case RestaurantFloorFixtureKind.exit:
        return 'خروج';
      case RestaurantFloorFixtureKind.bathroom:
        return 'حمّام';
      case RestaurantFloorFixtureKind.stairs:
        return 'درج';
      case RestaurantFloorFixtureKind.text:
        return 'نص';
      case RestaurantFloorFixtureKind.arrow:
        return 'سهم';
      case RestaurantFloorFixtureKind.wall:
        return 'جدار';
      case RestaurantFloorFixtureKind.zoneSeating:
        return 'منطقة جلوس';
      case RestaurantFloorFixtureKind.zoneKitchen:
        return 'منطقة مطبخ';
      case RestaurantFloorFixtureKind.zoneCashier:
        return 'منطقة كاشير';
      case RestaurantFloorFixtureKind.zoneBathroom:
        return 'منطقة حمّامات';
      case RestaurantFloorFixtureKind.hallFrame:
        return 'إطار القاعة';
    }
  }

  bool get isZone =>
      this == RestaurantFloorFixtureKind.zoneSeating ||
      this == RestaurantFloorFixtureKind.zoneKitchen ||
      this == RestaurantFloorFixtureKind.zoneCashier ||
      this == RestaurantFloorFixtureKind.zoneBathroom;

  static RestaurantFloorFixtureKind fromDb(String raw) {
    switch (raw) {
      case 'cashier':
        return RestaurantFloorFixtureKind.cashier;
      case 'entrance':
        return RestaurantFloorFixtureKind.entrance;
      case 'exit':
        return RestaurantFloorFixtureKind.exit;
      case 'bathroom':
        return RestaurantFloorFixtureKind.bathroom;
      case 'stairs':
        return RestaurantFloorFixtureKind.stairs;
      case 'text':
        return RestaurantFloorFixtureKind.text;
      case 'arrow':
        return RestaurantFloorFixtureKind.arrow;
      case 'wall':
        return RestaurantFloorFixtureKind.wall;
      case 'zone_seating':
        return RestaurantFloorFixtureKind.zoneSeating;
      case 'zone_kitchen':
        return RestaurantFloorFixtureKind.zoneKitchen;
      case 'zone_cashier':
        return RestaurantFloorFixtureKind.zoneCashier;
      case 'zone_bathroom':
        return RestaurantFloorFixtureKind.zoneBathroom;
      case 'hall_frame':
        return RestaurantFloorFixtureKind.hallFrame;
      default:
        return RestaurantFloorFixtureKind.text;
    }
  }
}

class RestaurantTable {
  const RestaurantTable({
    required this.id,
    required this.tenantId,
    required this.floorId,
    required this.tableNumber,
    required this.tableSlug,
    required this.sessionSeq,
    this.capacity,
    this.deletedAt,
    this.derivedState = DerivedTableState.available,
    this.activeSessionId,
    this.sessionOpenedAt,
    this.layoutXBp = -1,
    this.layoutYBp = -1,
    this.layoutRotDeg = 0,
    this.seatStyle = RestaurantTableSeatStyle.center,
    this.layoutWBp = 900,
    this.layoutHBp = 900,
  });

  final int id;
  final int tenantId;
  final int floorId;
  final String tableNumber;
  final String tableSlug;
  final int sessionSeq;
  final int? capacity;
  final int? deletedAt;
  final DerivedTableState derivedState;
  final int? activeSessionId;
  /// وقت فتح الجلسة النشطة (epoch ms) — لعداد الانشغال.
  final int? sessionOpenedAt;
  /// موضع حر على القاعة: 0–10000 = 0%–100%. القيمة -1 = توزيع تلقائي.
  final int layoutXBp;
  final int layoutYBp;
  final int layoutRotDeg;
  final RestaurantTableSeatStyle seatStyle;
  final int layoutWBp;
  final int layoutHBp;

  int get seatCount {
    final c = capacity ?? 4;
    if (c >= 6) return 6;
    return 4;
  }

  factory RestaurantTable.fromMap(
    Map<String, Object?> m, {
    DerivedTableState derivedState = DerivedTableState.available,
    int? activeSessionId,
    int? sessionOpenedAt,
  }) =>
      RestaurantTable(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        floorId: m['floor_id'] as int,
        tableNumber: m['table_number'] as String,
        tableSlug: m['table_slug'] as String,
        sessionSeq: (m['session_seq'] as int?) ?? 0,
        capacity: m['capacity'] as int?,
        deletedAt: m['deleted_at'] as int?,
        derivedState: derivedState,
        activeSessionId: activeSessionId,
        sessionOpenedAt: sessionOpenedAt,
        layoutXBp: (m['layout_x_bp'] as int?) ?? -1,
        layoutYBp: (m['layout_y_bp'] as int?) ?? -1,
        layoutRotDeg: (m['layout_rot_deg'] as int?) ?? 0,
        seatStyle: (m['seat_style'] as String?) == 'wall'
            ? RestaurantTableSeatStyle.wall
            : RestaurantTableSeatStyle.center,
        layoutWBp: (m['layout_w_bp'] as int?) ?? 900,
        layoutHBp: (m['layout_h_bp'] as int?) ?? 900,
      );
}

class RestaurantFloorFixture {
  const RestaurantFloorFixture({
    required this.id,
    required this.tenantId,
    required this.floorId,
    required this.kind,
    required this.layoutXBp,
    required this.layoutYBp,
    required this.layoutWBp,
    required this.layoutHBp,
    this.labelAr,
    this.layoutRotDeg = 0,
    this.metaJson,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final int floorId;
  final RestaurantFloorFixtureKind kind;
  final String? labelAr;
  final int layoutXBp;
  final int layoutYBp;
  final int layoutWBp;
  final int layoutHBp;
  final int layoutRotDeg;
  final String? metaJson;
  final int? deletedAt;

  factory RestaurantFloorFixture.fromMap(Map<String, Object?> m) =>
      RestaurantFloorFixture(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        floorId: m['floor_id'] as int,
        kind: RestaurantFloorFixtureKindX.fromDb(m['kind'] as String? ?? 'text'),
        labelAr: m['label_ar'] as String?,
        layoutXBp: (m['layout_x_bp'] as int?) ?? 1000,
        layoutYBp: (m['layout_y_bp'] as int?) ?? 1000,
        layoutWBp: (m['layout_w_bp'] as int?) ?? 1200,
        layoutHBp: (m['layout_h_bp'] as int?) ?? 900,
        layoutRotDeg: (m['layout_rot_deg'] as int?) ?? 0,
        metaJson: m['meta_json'] as String?,
        deletedAt: m['deleted_at'] as int?,
      );
}

enum RestaurantSessionState { open, awaitingPayment, closed }

enum RestaurantChannel { qrTable, publicLink, cashier }

class RestaurantSession {
  const RestaurantSession({
    required this.id,
    required this.tenantId,
    required this.sessionSeq,
    required this.channel,
    required this.state,
    required this.invoiceId,
    required this.openedAt,
    this.tableId,
    this.closedAt,
    this.clientFingerprint,
  });

  final int id;
  final int tenantId;
  final int? tableId;
  final int sessionSeq;
  final RestaurantChannel channel;
  final RestaurantSessionState state;
  final int invoiceId;
  final int openedAt;
  final int? closedAt;
  final String? clientFingerprint;

  factory RestaurantSession.fromMap(Map<String, Object?> m) {
    return RestaurantSession(
      id: m['id'] as int,
      tenantId: m['tenant_id'] as int,
      tableId: m['table_id'] as int?,
      sessionSeq: m['session_seq'] as int,
      channel: _channelFromDb(m['channel'] as String?),
      state: _stateFromDb(m['state'] as String?),
      invoiceId: m['invoice_id'] as int,
      openedAt: m['opened_at'] as int,
      closedAt: m['closed_at'] as int?,
      clientFingerprint: m['client_fingerprint'] as String?,
    );
  }

  static RestaurantChannel _channelFromDb(String? raw) {
    switch (raw) {
      case 'public_link':
        return RestaurantChannel.publicLink;
      case 'cashier':
        return RestaurantChannel.cashier;
      case 'qr_table':
      default:
        return RestaurantChannel.qrTable;
    }
  }

  static RestaurantSessionState _stateFromDb(String? raw) {
    switch (raw) {
      case 'awaiting_payment':
        return RestaurantSessionState.awaitingPayment;
      case 'closed':
        return RestaurantSessionState.closed;
      case 'open':
      default:
        return RestaurantSessionState.open;
    }
  }

  static String channelToDb(RestaurantChannel c) {
    switch (c) {
      case RestaurantChannel.publicLink:
        return 'public_link';
      case RestaurantChannel.cashier:
        return 'cashier';
      case RestaurantChannel.qrTable:
        return 'qr_table';
    }
  }

  static String stateToDb(RestaurantSessionState s) {
    switch (s) {
      case RestaurantSessionState.awaitingPayment:
        return 'awaiting_payment';
      case RestaurantSessionState.closed:
        return 'closed';
      case RestaurantSessionState.open:
        return 'open';
    }
  }
}

class RestaurantMenuCategory {
  const RestaurantMenuCategory({
    required this.id,
    required this.tenantId,
    required this.nameAr,
    required this.sortOrder,
    required this.isActive,
  });

  final int id;
  final int tenantId;
  final String nameAr;
  final int sortOrder;
  final bool isActive;

  factory RestaurantMenuCategory.fromMap(Map<String, Object?> m) =>
      RestaurantMenuCategory(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        nameAr: m['name_ar'] as String,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        isActive: ((m['is_active'] as int?) ?? 1) == 1,
      );
}

class RestaurantMenuItem {
  const RestaurantMenuItem({
    required this.id,
    required this.tenantId,
    required this.categoryId,
    required this.nameAr,
    required this.priceFils,
    required this.isAvailable,
    required this.sortOrder,
    this.descriptionAr,
    this.imageUrl,
    this.channelsJson = '["qr_table","public_link","cashier"]',
    this.directStockSkuId,
    this.hasRecipe = false,
  });

  final int id;
  final int tenantId;
  final int categoryId;
  final String nameAr;
  final String? descriptionAr;
  final int priceFils;
  final String? imageUrl;
  final bool isAvailable;
  final String channelsJson;
  final int? directStockSkuId;
  final int sortOrder;
  final bool hasRecipe;

  bool get canBeAvailable => hasRecipe || directStockSkuId != null;

  factory RestaurantMenuItem.fromMap(
    Map<String, Object?> m, {
    bool hasRecipe = false,
  }) =>
      RestaurantMenuItem(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        categoryId: m['category_id'] as int,
        nameAr: m['name_ar'] as String,
        descriptionAr: m['description_ar'] as String?,
        priceFils: m['price_fils'] as int,
        imageUrl: m['image_url'] as String?,
        isAvailable: ((m['is_available'] as int?) ?? 0) == 1,
        channelsJson: (m['channels_json'] as String?) ??
            '["qr_table","public_link","cashier"]',
        directStockSkuId: m['direct_stock_sku_id'] as int?,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        hasRecipe: hasRecipe,
      );
}

class RestaurantRecipe {
  const RestaurantRecipe({
    required this.id,
    required this.tenantId,
    required this.menuItemId,
    required this.yieldQty,
    this.notesAr,
  });

  final int id;
  final int tenantId;
  final int menuItemId;
  final int yieldQty;
  final String? notesAr;

  factory RestaurantRecipe.fromMap(Map<String, Object?> m) => RestaurantRecipe(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        menuItemId: m['menu_item_id'] as int,
        yieldQty: (m['yield_qty'] as int?) ?? 1,
        notesAr: m['notes_ar'] as String?,
      );
}

enum RecipeBaseUnit { g, ml, piece }

class RestaurantRecipeLine {
  const RestaurantRecipeLine({
    required this.id,
    required this.recipeId,
    required this.productId,
    required this.baseUnit,
    required this.qtyMicro,
    required this.isCritical,
    required this.sortOrder,
    this.productNameAr,
  });

  final int id;
  final int recipeId;
  final int productId;
  final RecipeBaseUnit baseUnit;
  final int qtyMicro;
  final bool isCritical;
  final int sortOrder;
  final String? productNameAr;

  static RecipeBaseUnit unitFromDb(String? raw) {
    switch (raw) {
      case 'ml':
        return RecipeBaseUnit.ml;
      case 'piece':
        return RecipeBaseUnit.piece;
      case 'g':
      default:
        return RecipeBaseUnit.g;
    }
  }

  static String unitToDb(RecipeBaseUnit u) {
    switch (u) {
      case RecipeBaseUnit.ml:
        return 'ml';
      case RecipeBaseUnit.piece:
        return 'piece';
      case RecipeBaseUnit.g:
        return 'g';
    }
  }

  factory RestaurantRecipeLine.fromMap(Map<String, Object?> m) =>
      RestaurantRecipeLine(
        id: m['id'] as int,
        recipeId: m['recipe_id'] as int,
        productId: m['product_id'] as int,
        baseUnit: unitFromDb(m['base_unit'] as String?),
        qtyMicro: m['qty_micro'] as int,
        isCritical: ((m['is_critical'] as int?) ?? 1) == 1,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        productNameAr: m['product_name'] as String?,
      );
}

class RestaurantMenuItemImage {
  const RestaurantMenuItemImage({
    required this.id,
    required this.tenantId,
    required this.menuItemId,
    required this.imageUrl,
    required this.variantsJson,
    required this.sortOrder,
    required this.isPrimary,
    required this.mime,
    this.widthPx,
    this.heightPx,
    this.bytes,
    this.altAr,
    this.altEn,
  });

  final int id;
  final int tenantId;
  final int menuItemId;
  final String imageUrl;
  final String variantsJson;
  final int sortOrder;
  final bool isPrimary;
  final String mime;
  final int? widthPx;
  final int? heightPx;
  final int? bytes;
  final String? altAr;
  final String? altEn;

  factory RestaurantMenuItemImage.fromMap(Map<String, Object?> m) =>
      RestaurantMenuItemImage(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        menuItemId: m['menu_item_id'] as int,
        imageUrl: m['image_url'] as String,
        variantsJson: m['variants_json'] as String,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        isPrimary: ((m['is_primary'] as int?) ?? 0) == 1,
        mime: m['mime'] as String,
        widthPx: m['width_px'] as int?,
        heightPx: m['height_px'] as int?,
        bytes: m['bytes'] as int?,
        altAr: m['alt_ar'] as String?,
        altEn: m['alt_en'] as String?,
      );
}

class RestaurantMenuThemeRow {
  const RestaurantMenuThemeRow({
    required this.id,
    required this.tenantId,
    required this.draftJson,
    required this.draftVersion,
    required this.publishedVersion,
    required this.menuContentVersion,
    required this.updatedAt,
    this.publishedJson,
    this.publishedAt,
    this.publishedBy,
    this.updatedBy,
  });

  final int id;
  final int tenantId;
  final String draftJson;
  final String? publishedJson;
  final int draftVersion;
  final int publishedVersion;
  final int menuContentVersion;
  final int updatedAt;
  final int? publishedAt;
  final int? publishedBy;
  final int? updatedBy;

  bool get hasUnpublishedChanges =>
      draftVersion != publishedVersion ||
      (publishedJson == null && draftJson.isNotEmpty);

  factory RestaurantMenuThemeRow.fromMap(Map<String, Object?> m) =>
      RestaurantMenuThemeRow(
        id: m['id'] as int,
        tenantId: m['tenant_id'] as int,
        draftJson: m['draft_json'] as String,
        publishedJson: m['published_json'] as String?,
        draftVersion: (m['draft_version'] as int?) ?? 0,
        publishedVersion: (m['published_version'] as int?) ?? 0,
        menuContentVersion: (m['menu_content_version'] as int?) ?? 0,
        updatedAt: m['updated_at'] as int,
        publishedAt: m['published_at'] as int?,
        publishedBy: m['published_by'] as int?,
        updatedBy: m['updated_by'] as int?,
      );
}

enum RestaurantOrderState {
  newOrder,
  accepted,
  preparing,
  ready,
  served,
  voided,
}

enum RestaurantOrderLineState {
  active,
  voidedStockShortfall,
  voidedByCashier,
}

class RestaurantOrder {
  const RestaurantOrder({
    required this.id,
    required this.tenantId,
    required this.sessionId,
    required this.invoiceId,
    required this.channel,
    required this.state,
    required this.createdAt,
    this.acceptedAt,
    this.preparingAt,
    this.readyAt,
    this.servedAt,
    this.notesAr,
    this.clientGeneratedId,
    this.tableNumber,
    this.lines = const [],
  });

  final int id;
  final int tenantId;
  final int sessionId;
  final int invoiceId;
  final RestaurantChannel channel;
  final RestaurantOrderState state;
  final int createdAt;
  final int? acceptedAt;
  final int? preparingAt;
  final int? readyAt;
  final int? servedAt;
  final String? notesAr;
  final String? clientGeneratedId;
  final String? tableNumber;
  final List<RestaurantOrderLine> lines;

  static RestaurantOrderState stateFromDb(String? raw) {
    switch (raw) {
      case 'accepted':
        return RestaurantOrderState.accepted;
      case 'preparing':
        return RestaurantOrderState.preparing;
      case 'ready':
        return RestaurantOrderState.ready;
      case 'served':
        return RestaurantOrderState.served;
      case 'voided':
        return RestaurantOrderState.voided;
      case 'new':
      default:
        return RestaurantOrderState.newOrder;
    }
  }

  static String stateToDb(RestaurantOrderState s) {
    switch (s) {
      case RestaurantOrderState.accepted:
        return 'accepted';
      case RestaurantOrderState.preparing:
        return 'preparing';
      case RestaurantOrderState.ready:
        return 'ready';
      case RestaurantOrderState.served:
        return 'served';
      case RestaurantOrderState.voided:
        return 'voided';
      case RestaurantOrderState.newOrder:
        return 'new';
    }
  }

  String get stateLabelAr {
    switch (state) {
      case RestaurantOrderState.newOrder:
        return 'جديد';
      case RestaurantOrderState.accepted:
        return 'مقبول';
      case RestaurantOrderState.preparing:
        return 'قيد التحضير';
      case RestaurantOrderState.ready:
        return 'جاهز';
      case RestaurantOrderState.served:
        return 'مُسلَّم';
      case RestaurantOrderState.voided:
        return 'ملغى';
    }
  }

  factory RestaurantOrder.fromMap(
    Map<String, Object?> m, {
    List<RestaurantOrderLine> lines = const [],
  }) {
    return RestaurantOrder(
      id: m['id'] as int,
      tenantId: m['tenant_id'] as int,
      sessionId: m['session_id'] as int,
      invoiceId: m['invoice_id'] as int,
      channel: RestaurantSession._channelFromDb(m['channel'] as String?),
      state: stateFromDb(m['state'] as String?),
      createdAt: m['created_at'] as int,
      acceptedAt: m['accepted_at'] as int?,
      preparingAt: m['preparing_at'] as int?,
      readyAt: m['ready_at'] as int?,
      servedAt: m['served_at'] as int?,
      notesAr: m['notes_ar'] as String?,
      clientGeneratedId: m['client_generated_id'] as String?,
      tableNumber: m['table_number'] as String?,
      lines: lines,
    );
  }
}

class RestaurantOrderLine {
  const RestaurantOrderLine({
    required this.id,
    required this.orderId,
    required this.menuItemId,
    required this.qty,
    required this.unitPriceFilsAtSale,
    required this.lineState,
    this.modifiersJson,
    this.voidReasonAr,
    this.notesAr,
    this.menuItemNameAr,
  });

  final int id;
  final int orderId;
  final int menuItemId;
  final int qty;
  final int unitPriceFilsAtSale;
  final RestaurantOrderLineState lineState;
  final String? modifiersJson;
  final String? voidReasonAr;
  final String? notesAr;
  final String? menuItemNameAr;

  int get lineTotalFils => unitPriceFilsAtSale * qty;

  static RestaurantOrderLineState lineStateFromDb(String? raw) {
    switch (raw) {
      case 'voided_stock_shortfall':
        return RestaurantOrderLineState.voidedStockShortfall;
      case 'voided_by_cashier':
        return RestaurantOrderLineState.voidedByCashier;
      case 'active':
      default:
        return RestaurantOrderLineState.active;
    }
  }

  static String lineStateToDb(RestaurantOrderLineState s) {
    switch (s) {
      case RestaurantOrderLineState.voidedStockShortfall:
        return 'voided_stock_shortfall';
      case RestaurantOrderLineState.voidedByCashier:
        return 'voided_by_cashier';
      case RestaurantOrderLineState.active:
        return 'active';
    }
  }

  factory RestaurantOrderLine.fromMap(Map<String, Object?> m) =>
      RestaurantOrderLine(
        id: m['id'] as int,
        orderId: m['order_id'] as int,
        menuItemId: m['menu_item_id'] as int,
        qty: m['qty'] as int,
        unitPriceFilsAtSale: m['unit_price_fils_at_sale'] as int,
        modifiersJson: m['modifiers_json'] as String?,
        lineState: lineStateFromDb(m['line_state'] as String?),
        voidReasonAr: m['void_reason_ar'] as String?,
        notesAr: m['notes_ar'] as String?,
        menuItemNameAr: m['menu_item_name'] as String?,
      );
}

class IngredientNeed {
  const IngredientNeed({
    required this.productId,
    required this.qtyMicroNeeded,
    required this.isCritical,
    this.nameAr,
    this.baseUnit = RecipeBaseUnit.g,
  });

  final int productId;
  final int qtyMicroNeeded;
  final bool isCritical;
  final String? nameAr;
  final RecipeBaseUnit baseUnit;
}

class IngredientShortageException implements Exception {
  IngredientShortageException({
    required this.productId,
    required this.availableMicro,
    required this.requestedMicro,
    this.nameAr,
  });

  final int productId;
  final int availableMicro;
  final int requestedMicro;
  final String? nameAr;

  @override
  String toString() =>
      'نقص مكوّن${nameAr != null ? ' «$nameAr»' : ''}: '
      'المطلوب $requestedMicro ميكرو، المتاح $availableMicro';
}

/// تحويل مخزون Core (`products.qty` REAL) ↔ qty_micro (spec).
/// تعارض موثّق: Core لا يملك عمود `on_hand_qty_micro`.
abstract final class RestaurantStockMicro {
  RestaurantStockMicro._();

  static int fromQty(num qty) => (qty * 1000).round();

  static double toQty(int qtyMicro) => qtyMicro / 1000.0;
}
