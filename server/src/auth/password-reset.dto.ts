import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsEmail, IsString, Length, Matches, MaxLength } from 'class-validator';

export class ForgotPasswordDto {
  @ApiProperty({ example: 'racer@example.com', maxLength: 254 })
  @Transform(({ value }) =>
    typeof value === 'string' ? value.trim().toLowerCase() : value,
  )
  @IsEmail()
  @MaxLength(254)
  email!: string;
}

export class ResetPasswordDto extends ForgotPasswordDto {
  @ApiProperty({ example: '123456', minLength: 6, maxLength: 6 })
  @IsString()
  @Matches(/^\d{6}$/)
  otp!: string;

  @ApiProperty({ minLength: 8, maxLength: 128, format: 'password' })
  @IsString()
  @Length(8, 128)
  newPassword!: string;
}
