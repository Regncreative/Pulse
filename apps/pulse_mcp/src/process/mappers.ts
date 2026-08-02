import type { HealthProcessEntry, ProcessDetails } from "../health/types.js";

export interface ProcessListFilters {
  query?: string;
  cpuAbove?: number;
  memoryAboveBytes?: number;
  company?: string;
  signed?: boolean;
  running?: boolean;
  applicationOnly?: boolean;
  backgroundOnly?: boolean;
  systemOnly?: boolean;
  nameContains?: string;
  limit?: number;
  offset?: number;
  sortBy?: "cpu" | "memory" | "name" | "pid";
  sortDir?: "asc" | "desc";
}

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 500;

/** Secret-like cmdline tokens → *** (doc 33). */
const SECRET_PAIR =
  /((?:--)?(?:api[_-]?key|token|password|secret|passwd|pwd|auth|bearer|access[_-]?key))([=\s:]+)([^\s"']+)/gi;

export function redactCommandLine(cmdline: string): string {
  return cmdline.replace(SECRET_PAIR, (_m, key: string, sep: string) => `${key}${sep}***`);
}

export function processStableId(entry: HealthProcessEntry): string {
  if (entry.hasCreateTime) return `${entry.pid}:${entry.createTimeUnixMs}`;
  return String(entry.pid);
}

function memoryBytes(entry: HealthProcessEntry): number | null {
  if (entry.hasWorkingSetBytes) return entry.workingSetBytes;
  if (entry.hasMemoryBytes) return entry.memoryBytes;
  return null;
}

function isSystemPath(path: string): boolean {
  const lower = path.toLowerCase().replace(/\//g, "\\");
  return (
    lower.includes("\\windows\\system32\\") ||
    lower.includes("\\windows\\syswow64\\") ||
    lower.startsWith("c:\\windows\\")
  );
}

export function mapProcessRow(entry: HealthProcessEntry): Record<string, unknown> {
  const unavailable: Record<string, string> = {};
  // Not on HealthProcessEntry wire — honest nulls.
  unavailable.company = "Not in process inventory; use process.details";
  unavailable.description = "Not in process inventory; use process.details";
  unavailable.signed = "Not supported on inventory wire";
  unavailable.hasWindow = "Not supported on inventory wire";
  unavailable.integrity = "Not in process inventory; use process.details";

  return {
    id: processStableId(entry),
    pid: entry.pid,
    name: entry.name || null,
    path: entry.path || null,
    cpuPercent: entry.hasCpuPercent ? entry.cpuPercent : null,
    workingSetBytes: memoryBytes(entry),
    privateBytes: entry.hasCommitBytes ? entry.commitBytes : null,
    company: null,
    description: null,
    signed: null,
    hasWindow: null,
    integrity: null,
    threadCount: entry.threadCount || null,
    handleCount: entry.handleCount || null,
    createTime:
      entry.hasCreateTime
        ? new Date(entry.createTimeUnixMs).toISOString()
        : null,
    unavailable,
  };
}

export function filterSortProcesses(
  entries: HealthProcessEntry[],
  filters: ProcessListFilters,
): {
  processes: Record<string, unknown>[];
  count: number;
  truncated: boolean;
  filtersIgnored: string[];
} {
  const limit = Math.min(
    Math.max(1, filters.limit ?? DEFAULT_LIMIT),
    MAX_LIMIT,
  );
  const offset = Math.max(0, filters.offset ?? 0);
  const sortBy = filters.sortBy ?? "cpu";
  const sortDir = filters.sortDir ?? "desc";
  const dir = sortDir === "asc" ? 1 : -1;

  let list = [...entries];

  if (filters.nameContains) {
    const q = filters.nameContains.toLowerCase();
    list = list.filter(
      (e) =>
        e.name.toLowerCase().includes(q) || e.path.toLowerCase().includes(q),
    );
  }

  if (filters.query) {
    const q = filters.query.toLowerCase();
    list = list.filter(
      (e) =>
        e.name.toLowerCase().includes(q) || e.path.toLowerCase().includes(q),
    );
  }

  if (typeof filters.cpuAbove === "number") {
    list = list.filter(
      (e) => e.hasCpuPercent && e.cpuPercent >= filters.cpuAbove!,
    );
  }

  if (typeof filters.memoryAboveBytes === "number") {
    list = list.filter((e) => {
      const mem = memoryBytes(e);
      return mem !== null && mem >= filters.memoryAboveBytes!;
    });
  }

  if (filters.running === false) {
    list = [];
  }

  // Heuristics only — inventory has no window/company flags.
  if (filters.systemOnly) {
    list = list.filter((e) => isSystemPath(e.path) || e.hasIsCritical && e.isCritical);
  }
  if (filters.applicationOnly) {
    list = list.filter((e) => e.path && !isSystemPath(e.path));
  }
  if (filters.backgroundOnly) {
    // Without hasWindow, approximate: system paths + low name specificity.
    list = list.filter((e) => isSystemPath(e.path) || !e.path);
  }

  const filtersIgnored: string[] = [];
  if (filters.company) filtersIgnored.push("company");
  if (filters.signed !== undefined) filtersIgnored.push("signed");

  list.sort((a, b) => {
    let cmp = 0;
    switch (sortBy) {
      case "pid":
        cmp = a.pid - b.pid;
        break;
      case "name":
        cmp = a.name.localeCompare(b.name);
        break;
      case "memory":
        cmp = (memoryBytes(a) ?? 0) - (memoryBytes(b) ?? 0);
        break;
      case "cpu":
      default:
        cmp = (a.hasCpuPercent ? a.cpuPercent : 0) - (b.hasCpuPercent ? b.cpuPercent : 0);
        break;
    }
    return cmp * dir;
  });

  const total = list.length;
  const page = list.slice(offset, offset + limit);
  return {
    count: page.length,
    truncated: offset + page.length < total,
    processes: page.map(mapProcessRow),
    filtersIgnored,
  };
}

export function mapProcessDetails(
  details: ProcessDetails,
  live?: HealthProcessEntry,
): Record<string, unknown> {
  const unavailable: Record<string, string> = {};
  const cmdline =
    details.hasCommandLine && details.commandLine
      ? redactCommandLine(details.commandLine)
      : null;
  if (!details.hasCommandLine) unavailable.commandLine = "Not available";
  if (!details.hasPath) unavailable.path = "Not available";
  if (!details.hasCompany) unavailable.company = "Not available";
  if (!details.hasUser) unavailable.user = "Not available";
  if (!details.hasParentPid) unavailable.parentPid = "Not available";
  if (!details.hasElevated) unavailable.elevated = "Not available";
  if (!details.hasArchitecture) unavailable.architecture = "Not available";
  if (!details.hasIntegrityLevel) unavailable.integrity = "Not available";

  return {
    id:
      details.hasCreateTime
        ? `${details.pid}:${details.createTimeUnixMs}`
        : String(details.pid),
    pid: details.pid,
    name: details.name || null,
    path: details.hasPath ? details.path || null : null,
    company: details.hasCompany ? details.company || null : null,
    description: details.hasProductName ? details.productName || null : null,
    commandLine: cmdline,
    parentPid: details.hasParentPid ? details.parentPid : null,
    parentName: details.hasParentName ? details.parentName || null : null,
    user: details.hasUser ? details.user || null : null,
    integrity: details.hasIntegrityLevel
      ? details.integrityLevel || null
      : null,
    elevated: details.hasElevated ? details.elevated : null,
    architecture: details.hasArchitecture
      ? details.architecture || null
      : null,
    startTime: details.hasCreateTime
      ? new Date(details.createTimeUnixMs).toISOString()
      : null,
    threadCount: details.threadCount || null,
    handleCount: details.handleCount || null,
    cpuPercent: live?.hasCpuPercent ? live.cpuPercent : null,
    workingSetBytes: live
      ? live.hasWorkingSetBytes
        ? live.workingSetBytes
        : live.hasMemoryBytes
          ? live.memoryBytes
          : null
      : null,
    privateBytes: live?.hasCommitBytes ? live.commitBytes : null,
    unavailable:
      Object.keys(unavailable).length > 0 ? unavailable : undefined,
  };
}
