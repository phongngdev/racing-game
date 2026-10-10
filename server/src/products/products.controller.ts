import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user.schema.js';
import { ProductDto, ProductInputDto } from './product.dto.js';
import { ProductsService } from './products.service.js';

@ApiTags('products')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Bearer token is missing or invalid.' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('products')
export class ProductsController {
  constructor(private readonly products: ProductsService) {}

  @Get()
  @ApiOperation({ summary: 'List products.' })
  @ApiOkResponse({ type: ProductDto, isArray: true })
  findAll(): Promise<ProductDto[]> {
    return this.products.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a product by id.' })
  @ApiParam({ name: 'id', description: 'MongoDB ObjectId.' })
  @ApiOkResponse({ type: ProductDto })
  @ApiBadRequestResponse({ description: 'The id is not a valid ObjectId.' })
  @ApiNotFoundResponse({ description: 'Product not found.' })
  findOne(@Param('id') id: string): Promise<ProductDto> {
    return this.products.findOne(id);
  }

  @Post()
  @Roles(UserRole.Admin)
  @ApiOperation({ summary: 'Create a product (Admin only).' })
  @ApiCreatedResponse({ type: ProductDto })
  @ApiBadRequestResponse({ description: 'The request body is invalid.' })
  @ApiNotFoundResponse({ description: 'Category not found.' })
  @ApiForbiddenResponse({ description: 'Admin role is required.' })
  create(@Body() input: ProductInputDto): Promise<ProductDto> {
    return this.products.create(input);
  }

  @Put(':id')
  @Roles(UserRole.Admin)
  @ApiOperation({ summary: 'Replace a product (Admin only).' })
  @ApiParam({ name: 'id', description: 'MongoDB ObjectId.' })
  @ApiOkResponse({ type: ProductDto })
  @ApiBadRequestResponse({ description: 'The id or request body is invalid.' })
  @ApiNotFoundResponse({ description: 'Product or category not found.' })
  @ApiForbiddenResponse({ description: 'Admin role is required.' })
  replace(
    @Param('id') id: string,
    @Body() input: ProductInputDto,
  ): Promise<ProductDto> {
    return this.products.replace(id, input);
  }

  @Delete(':id')
  @Roles(UserRole.Admin)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete a product (Admin only).' })
  @ApiParam({ name: 'id', description: 'MongoDB ObjectId.' })
  @ApiNoContentResponse({ description: 'Product deleted.' })
  @ApiBadRequestResponse({ description: 'The id is not a valid ObjectId.' })
  @ApiNotFoundResponse({ description: 'Product not found.' })
  @ApiForbiddenResponse({ description: 'Admin role is required.' })
  async delete(@Param('id') id: string): Promise<void> {
    await this.products.delete(id);
  }
}
