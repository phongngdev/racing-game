import { randomBytes } from 'node:crypto';

process.env['MONGODB_URI'] = 'mongodb://127.0.0.1:27017/racing_game_test';
process.env['JWT_SECRET'] = randomBytes(48).toString('base64url');
process.env['JWT_EXPIRES_IN'] = '1h';
process.env['RESET_OTP_PEPPER'] = randomBytes(48).toString('base64url');
