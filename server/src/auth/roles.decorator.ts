import { SetMetadata } from '@nestjs/common';
import { UserRole } from '../users/user.schema.js';

export const ROLES_KEY = 'required-roles';
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
