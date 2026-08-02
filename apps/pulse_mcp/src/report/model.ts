import {
  MCP_SERVER_VERSION,
  PULSE_APP_VERSION,
} from "../version.js";
import type { GatheredReportData } from "./gather.js";
import { fileStemFor, type ReportModel, type ReportType } from "./types.js";

function deviceRows(
  view: GatheredReportData["usb"],
): Array<Record<string, unknown>> {
  if (!view) return [];
  return view.devices.map((d) => ({
    id: d.id || null,
    description: d.description || null,
    hardwareId: d.hardwareId || null,
    manufacturer: d.manufacturer || null,
    service: d.service || null,
    className: d.className || null,
  }));
}

export function buildReportModel(
  template: ReportType,
  data: GatheredReportData,
): ReportModel {
  const sections: Record<string, unknown> = {};

  switch (template) {
    case "health":
      sections.health = data.health;
      break;
    case "timeline":
      sections.timeline = {
        count: data.events.length,
        events: data.events,
      };
      break;
    case "diagnostics":
      sections.diagnostics = data.diagnostics;
      break;
    case "hardware":
      sections.source = "inventory_engine";
      sections.healthIdentity = data.health?.static ?? null;
      sections.usb = {
        status: data.usb?.status ?? null,
        statusDetail: data.usb?.statusDetail || null,
        truncated: data.usb?.truncated ?? false,
        count: data.usb?.devices.length ?? 0,
        devices: deviceRows(data.usb),
      };
      sections.pci = {
        status: data.pci?.status ?? null,
        statusDetail: data.pci?.statusDetail || null,
        truncated: data.pci?.truncated ?? false,
        count: data.pci?.devices.length ?? 0,
        devices: deviceRows(data.pci),
      };
      break;
    case "combined":
      sections.health = data.health;
      sections.diagnostics = data.diagnostics;
      sections.timeline = {
        count: data.events.length,
        events: data.events,
      };
      break;
  }

  return {
    pulse_export: fileStemFor(template),
    template,
    version: 1,
    exported_at: new Date().toISOString(),
    pulse_version: PULSE_APP_VERSION,
    mcp_version: MCP_SERVER_VERSION,
    system_identity: data.identity,
    sections,
  };
}
