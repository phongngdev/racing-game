export type ControllerRole = 'game' | 'phone';
export type ProtocolVersion = 1 | 2 | 3;
export type MultiplayerSlotId = 'p1' | 'p2';
export type MultiplayerSource = 'phone' | 'keyboard';

export interface ControllerInput {
  seq: number;
  steering: number;
  throttle: number;
  reverse?: number;
  brake: number;
}

export function isControllerInput(value: unknown): value is ControllerInput {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  const input = value as Record<string, unknown>;
  return (
    Number.isSafeInteger(input['seq']) &&
    (input['seq'] as number) >= 0 &&
    typeof input['steering'] === 'number' &&
    Number.isFinite(input['steering']) &&
    input['steering'] >= -1 &&
    input['steering'] <= 1 &&
    typeof input['throttle'] === 'number' &&
    Number.isFinite(input['throttle']) &&
    input['throttle'] >= 0 &&
    input['throttle'] <= 1 &&
    typeof input['brake'] === 'number' &&
    Number.isFinite(input['brake']) &&
    input['brake'] >= 0 &&
    input['brake'] <= 1 &&
    (input['reverse'] === undefined ||
      (typeof input['reverse'] === 'number' &&
        Number.isFinite(input['reverse']) &&
        input['reverse'] >= 0 &&
        input['reverse'] <= 1))
  );
}

export function isRole(value: unknown): value is ControllerRole {
  return value === 'game' || value === 'phone';
}

export function isProtocolVersion(value: unknown): value is ProtocolVersion {
  return value === 1 || value === 2 || value === 3;
}

export function isMultiplayerSlot(value: unknown): value is MultiplayerSlotId {
  return value === 'p1' || value === 'p2';
}

export function isMultiplayerSource(value: unknown): value is MultiplayerSource {
  return value === 'phone' || value === 'keyboard';
}

export function allowedControllerOrigins(): Set<string> {
  const configured = (process.env['CONTROLLER_ALLOWED_ORIGINS'] ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const httpOrigins = (
    process.env['CORS_ORIGINS'] ??
    'http://localhost:5173,http://127.0.0.1:5173'
  )
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  return new Set([
    'http://localhost:5174',
    'http://127.0.0.1:5174',
    ...httpOrigins,
    ...configured,
  ]);
}
