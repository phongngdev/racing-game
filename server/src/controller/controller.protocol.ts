export type ControllerRole = 'game' | 'phone';

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

export function allowedControllerOrigins(): Set<string> {
  const configured = (process.env['CONTROLLER_ALLOWED_ORIGINS'] ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const httpOrigins = (process.env['CORS_ORIGINS'] ?? '')
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
