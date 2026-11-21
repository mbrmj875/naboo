import { z } from "zod";
import { BASRA_BOUNDS } from "@/lib/field-geo";

export const FieldInterestSchema = z.enum([
  "rejected",
  "warm",
  "interested",
  "purchased",
]);

export const LocationSourceSchema = z.enum(["gps", "manual"]);

export const SyncOpSchema = z.enum([
  "create_visit",
  "update_visit",
  "create_territory",
  "update_territory",
]);

const LatSchema = z.number().min(BASRA_BOUNDS.latMin).max(BASRA_BOUNDS.latMax);
const LngSchema = z.number().min(BASRA_BOUNDS.lngMin).max(BASRA_BOUNDS.lngMax);

export const SyncEnvelopeSchema = z.object({
  client_op_id: z.string().uuid(),
  operation_hash: z.string().length(64).regex(/^[a-f0-9]{64}$/i),
  op: SyncOpSchema,
  client_updated_at: z.string().datetime(),
});

export const CreateVisitSchema = SyncEnvelopeSchema.extend({
  op: z.literal("create_visit"),
  shop_name: z.string().trim().min(1).max(200),
  owner_name: z.string().trim().min(1).max(200),
  phone: z.string().trim().max(20).optional().nullable(),
  lat: LatSchema,
  lng: LngSchema,
  interest: FieldInterestSchema,
  notes: z.string().max(500).optional().nullable(),
  location_source: LocationSourceSchema,
  gps_accuracy: z.number().nonnegative().optional().nullable(),
  geo_confirmed: z.boolean().optional(),
  territory_id: z.string().uuid().optional().nullable(),
});

export const UpdateVisitSchema = SyncEnvelopeSchema.extend({
  op: z.literal("update_visit"),
  visit_id: z.string().uuid(),
  shop_name: z.string().trim().min(1).max(200).optional(),
  owner_name: z.string().trim().min(1).max(200).optional(),
  phone: z.string().trim().max(20).optional().nullable(),
  lat: LatSchema.optional(),
  lng: LngSchema.optional(),
  interest: FieldInterestSchema.optional(),
  notes: z.string().max(500).optional().nullable(),
  location_source: LocationSourceSchema.optional(),
  gps_accuracy: z.number().nonnegative().optional().nullable(),
  geo_confirmed: z.boolean().optional(),
});

export const CreateTerritorySchema = SyncEnvelopeSchema.extend({
  op: z.literal("create_territory"),
  name: z.string().trim().min(1).max(120),
  geom_geojson: z.object({
    type: z.literal("Polygon"),
    coordinates: z.array(z.array(z.tuple([z.number(), z.number()]))).min(1),
  }),
});

export const UpdateTerritorySchema = SyncEnvelopeSchema.extend({
  op: z.literal("update_territory"),
  territory_id: z.string().uuid(),
  status: z.enum(["active", "released"]).optional(),
  name: z.string().trim().min(1).max(120).optional(),
});

export const FieldLoginSchema = z.object({
  username: z.string().trim().min(2).max(64),
  password: z.string().min(4).max(128),
});

export const AdminCreateRepSchema = z.object({
  username: z.string().trim().min(2).max(64),
  password: z.string().min(6).max(128),
  display_name: z.string().trim().min(2).max(120),
});

export const AdminUpdateRepSchema = z.object({
  rep_id: z.string().uuid(),
  action: z.enum(["disable", "enable", "reset_password"]),
  disabled_reason: z.string().trim().max(300).optional(),
  password: z.string().min(6).max(128).optional(),
});

export type CreateVisitInput = z.infer<typeof CreateVisitSchema>;
export type UpdateVisitInput = z.infer<typeof UpdateVisitSchema>;
export type CreateTerritoryInput = z.infer<typeof CreateTerritorySchema>;
export type UpdateTerritoryInput = z.infer<typeof UpdateTerritorySchema>;
