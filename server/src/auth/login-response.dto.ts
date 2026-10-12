import { ApiProperty } from '@nestjs/swagger';
import { PublicUserDto } from '../users/public-user.dto.js';

export class LoginResponseDto {
  @ApiProperty({ description: 'Signed access token.' })
  accessToken!: string;

  @ApiProperty({ type: PublicUserDto })
  user!: PublicUserDto;
}
