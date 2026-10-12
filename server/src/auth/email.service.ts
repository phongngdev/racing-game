import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createTransport } from 'nodemailer';

@Injectable()
export class EmailService {
  constructor(private readonly config: ConfigService) {}

  async sendPasswordResetCode(to: string, code: string): Promise<void> {
    const host = this.config.get<string>('SMTP_HOST');
    const user = this.config.get<string>('SMTP_USER');
    const password = this.config.get<string>('SMTP_PASSWORD');
    const port = Number(this.config.get<string>('SMTP_PORT') ?? 587);
    if (!host || !user || !password || !Number.isInteger(port)) {
      throw new ServiceUnavailableException('Email delivery is unavailable.');
    }

    const transport = createTransport({
      host,
      port,
      secure: port === 465,
      auth: { user, pass: password },
      connectionTimeout: 5000,
      greetingTimeout: 5000,
      socketTimeout: 5000,
    });
    try {
      await transport.sendMail({
        from: this.config.get<string>('SMTP_FROM') ?? user,
        to,
        subject: 'Apex RC password reset code',
        text: `Your password reset code is ${code}. It expires in 5 minutes. If you did not request a reset, ignore this email.`,
      });
    } finally {
      transport.close();
    }
  }
}
