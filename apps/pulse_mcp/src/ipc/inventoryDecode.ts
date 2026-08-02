/**
 * Minimal GetInventoryDomain encode/decode (USB + PCI device rows).
 * Field numbers match pulse.proto.
 */

import { Reader, writeU64 } from "./pb.js";

export const INVENTORY_DOMAIN_USB = 4;
export const INVENTORY_DOMAIN_PCI = 5;

export interface InventoryDeviceRow {
  id: string;
  description: string;
  hardwareId: string;
  manufacturer: string;
  service: string;
  className: string;
}

export interface InventoryDomainView {
  domain: number;
  status: number;
  statusDetail: string;
  truncated: boolean;
  generatedAtUnixMs: number;
  devices: InventoryDeviceRow[];
}

export function encodeGetInventoryDomain(
  domain: number,
  limit: number,
): Uint8Array {
  const out: number[] = [];
  writeU64(1, domain, out);
  writeU64(2, 0, out); // force_refresh = false
  if (limit > 0) writeU64(4, limit, out);
  return Uint8Array.from(out);
}

function decodeDeviceEntry(data: Uint8Array): InventoryDeviceRow {
  const r = new Reader(data);
  const m: InventoryDeviceRow = {
    id: "",
    description: "",
    hardwareId: "",
    manufacturer: "",
    service: "",
    className: "",
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (wire === 2) {
      const s = r.readString();
      if (field === 1) m.id = s;
      else if (field === 2) m.description = s;
      else if (field === 3) m.hardwareId = s;
      else if (field === 4) m.manufacturer = s;
      else if (field === 5) m.service = s;
      else if (field === 6) m.className = s;
    } else {
      r.skip(wire);
    }
  }
  return m;
}

export function decodeInventoryDomainSnapshot(
  data: Uint8Array,
): InventoryDomainView {
  const r = new Reader(data);
  const m: InventoryDomainView = {
    domain: 0,
    status: 0,
    statusDetail: "",
    truncated: false,
    generatedAtUnixMs: 0,
    devices: [],
  };
  while (r.hasMore) {
    const tag = r.readVarint();
    const field = tag >>> 3;
    const wire = tag & 7;
    if (field === 1 && wire === 0) m.domain = r.readVarint();
    else if (field === 2 && wire === 0) m.status = r.readVarint();
    else if (field === 3 && wire === 2) m.statusDetail = r.readString();
    else if (field === 4 && wire === 0) m.truncated = r.readVarint() !== 0;
    else if (field === 6 && wire === 0)
      m.generatedAtUnixMs = Number(r.readVarintBig());
    else if ((field === 13 || field === 14) && wire === 2) {
      m.devices.push(decodeDeviceEntry(r.readBytes()));
    } else {
      r.skip(wire);
    }
  }
  return m;
}
