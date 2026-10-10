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
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
  ApiForbiddenResponse,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import { Roles } from '../auth/roles.decorator.js';
import { RolesGuard } from '../auth/roles.guard.js';
import { UserRole } from '../users/user.schema.js';
import { CategoryDto, CategoryInputDto } from './category.dto.js';
import { CategoriesService } from './categories.service.js';

@ApiTags('categories')
@ApiBearerAuth()
@ApiUnauthorizedResponse({ description: 'Bearer token is missing or invalid.' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('categories')
export class CategoriesController {
  constructor(private readonly categories: CategoriesService) {}

  @Get()
  @ApiOperation({ summary: 'List categories.' })
  @ApiOkResponse({ type: CategoryDto, isArray: true })
  findAll(): Promise<CategoryDto[]> {
    return this.categories.findAll();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a category by id.' })
  @ApiParam({ name: 'id', description: 'MongoDB ObjectId.' })
  @ApiOkResponse({ type: CategoryDto })
  @ApiBadRequestResponse({ description: 'The id is not a valid ObjectId.' })
  @ApiNotFoundResponse({ description: 'Category not found.' })
  findOne(@Param('id') id: string): Promise<CategoryDto> {
    return this.categories.findOne(id);
  }

  @Post()
  @Roles(UserRole.Admin)
  @ApiOperation({ summary: 'Create a category (Admin only).' })
  @ApiCreatedResponse({ type: CategoryDto })
  @ApiBadRequestResponse({ description: 'The request body is invalid.' })
  @ApiConflictResponse({ description: 'The category name is already in use.' })
  @ApiForbiddenResponse({ description: 'Admin role is required.' })
  create(@Body() input: CategoryInputDto): Promise<CategoryDto> {
    return this.categories.create(input);
  }

  @Put(':id')
  @Roles(UserRole.Admin)
  @ApiOperation({ summary: 'Replace a category (Admin only).' })
  @ApiParam({ name: 'id', description: 'MongoDB ObjectId.' })
  @ApiOkResponse({ type: CategoryDto })
  @ApiBadRequestResponse({ description: 'The id or request body is invalid.' })
  @ApiNotFoundResponse({ description: 'Category not found.' })
  @ApiConflictResponse({ description: 'The category name is already in use.' })
  @ApiForbiddenResponse({ description: 'Admin role is required.' })
  replace(
    @Param('id') id: string,
    @Body() input: CategoryInputDto,
  ): Promise<CategoryDto> {
    return this.categories.replace(id, input);
  }

  @Delete(':id')
  @Roles(UserRole.Admin)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Delete a category and unlink its products (Admin only).',
  })
  @ApiParam({ name: 'id', description: 'MongoDB ObjectId.' })
  @ApiNoContentResponse({ description: 'Category deleted; products retained.' })
  @ApiBadRequestResponse({ description: 'The id is not a valid ObjectId.' })
  @ApiNotFoundResponse({ description: 'Category not found.' })
  @ApiForbiddenResponse({ description: 'Admin role is required.' })
  async delete(@Param('id') id: string): Promise<void> {
    await this.categories.delete(id);
  }
}
