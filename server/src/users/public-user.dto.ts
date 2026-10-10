import { ApiProperty } from '@nestjs/swagger';
import { UserRole } from './user.schema.js';

export class PublicUserDto {
  @ApiProperty({ example: '66c1a10d6b9a5e9a6a1c0123' })
  id!: string;

  @ApiProperty({ example: 'racer_01' })
  username!: string;

  @ApiProperty({ example: 'racer@example.com' })
  email!: string;

  @ApiProperty({ enum: UserRole, example: UserRole.User })
  role!: UserRole;
}

export interface PublicUser {
  id: string;
  username: string;
  email: string;
  role: UserRole;
}
