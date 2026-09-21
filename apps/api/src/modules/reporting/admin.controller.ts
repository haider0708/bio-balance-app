import { Controller,Get,Req } from '@nestjs/common';
import { ApiTags,ApiBearerAuth } from '@nestjs/swagger';
import { AuthRequest } from '../../shared/infrastructure/http';
import { AdminService } from './admin.service';
@ApiTags('administration') @ApiBearerAuth() @Controller('v1/admin')
export class AdminController {constructor(private readonly service:AdminService){} @Get('overview') overview(@Req() r:AuthRequest){return this.service.overview(r.actor);}}
