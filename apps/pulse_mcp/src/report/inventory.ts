import type { IpcSession } from "../ipc/session.js";
import { PulseIpcError } from "../ipc/session.js";
import {
  INVENTORY_DOMAIN_PCI,
  INVENTORY_DOMAIN_USB,
  type InventoryDomainView,
} from "../ipc/inventoryDecode.js";

export {
  INVENTORY_DOMAIN_PCI,
  INVENTORY_DOMAIN_USB,
  type InventoryDomainView,
  type InventoryDeviceRow,
} from "../ipc/inventoryDecode.js";

export async function fetchInventoryDomain(
  session: IpcSession,
  domain: number,
  limit = 500,
): Promise<InventoryDomainView> {
  const reply = await session.request(
    {
      type: "GetInventoryDomain",
      domain,
      limit,
    },
    15_000,
  );
  if (reply.body.type === "ErrorResponse") {
    throw new PulseIpcError(
      reply.body.message || "GetInventoryDomain failed",
      "INTERNAL_ERROR",
    );
  }
  if (reply.body.type !== "InventoryDomainSnapshot") {
    throw new PulseIpcError(
      `expected InventoryDomainSnapshot, got ${reply.body.type}`,
      "INTERNAL_ERROR",
    );
  }
  return reply.body.snapshot;
}
