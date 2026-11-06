export const APPLICATION_STATUSES = ["nueva", "contactada", "aprobada", "rechazada"] as const;
export type ApplicationStatus = (typeof APPLICATION_STATUSES)[number];

export function isApplicationStatus(value: unknown): value is ApplicationStatus {
  return typeof value === "string" && (APPLICATION_STATUSES as readonly string[]).includes(value);
}

/// Etiqueta en plural para las pestañas de filtro.
export function applicationTabLabel(status: ApplicationStatus): string {
  switch (status) {
    case "nueva":
      return "Nuevas";
    case "contactada":
      return "Contactadas";
    case "aprobada":
      return "Aprobadas";
    case "rechazada":
      return "Rechazadas";
  }
}
