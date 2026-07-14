export type OwnerAlertPrefs = {
  user_id: string;
  local_tenant_id: number;
  vertical: string;
  thresholds: Record<string, number>;
  push_alert_ids: string[];
  feature_flags?: OwnerAlertFeatureFlags;
};

export type OwnerAlertFeatureFlags = {
  enableDebts: boolean;
  enableInstallments: boolean;
};

export const DEFAULT_FEATURE_FLAGS: OwnerAlertFeatureFlags = {
  enableDebts: true,
  enableInstallments: true,
};

export type OwnerFcmToken = {
  token: string;
  platform: string;
};

export type SnapshotTables = Record<string, Array<Record<string, unknown>>>;

export type PushAlertCandidate = {
  alertId: string;
  actionKind: string;
  titleAr: string;
  bodyAr: string;
  tenantId: number;
  metricCount: number;
};

export type OwnerAlertThresholds = {
  stockShortageMinCount: number;
  variantShortageMinCount: number;
  slowMoversMinCount: number;
  slowMoversDays: number;
  garageStaleHours: number;
  garageStaleMinCount: number;
  activeGarageMinCount: number;
  debtorsMinCount: number;
  installmentOverdueMinCount: number;
  installmentDueTodayMinCount: number;
};

export const DEFAULT_THRESHOLDS: OwnerAlertThresholds = {
  stockShortageMinCount: 1,
  variantShortageMinCount: 1,
  slowMoversMinCount: 1,
  slowMoversDays: 30,
  garageStaleHours: 2,
  garageStaleMinCount: 1,
  activeGarageMinCount: 1,
  debtorsMinCount: 1,
  installmentOverdueMinCount: 1,
  installmentDueTodayMinCount: 1,
};
