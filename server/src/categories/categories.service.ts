import {
  ConflictException,
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { isObjectIdOrHexString, Model } from 'mongoose';
import { Product } from '../products/product.schema.js';
import { CategoryDto, CategoryInputDto } from './category.dto.js';
import { Category, CategoryDocument } from './category.schema.js';

@Injectable()
export class CategoriesService {
  constructor(
    @InjectModel(Category.name) private readonly categories: Model<Category>,
    @InjectModel(Product.name) private readonly products: Model<Product>,
  ) {}

  async findAll(): Promise<CategoryDto[]> {
    const categories = await this.categories.find().sort({ name: 1 }).exec();
    return categories.map((category) => this.toDto(category));
  }

  async findOne(id: string): Promise<CategoryDto> {
    this.assertObjectId(id);
    const category = await this.categories.findById(id).exec();
    if (!category) {
      throw new NotFoundException('Category not found.');
    }
    return this.toDto(category);
  }

  async create(input: CategoryInputDto): Promise<CategoryDto> {
    const name = input.name.trim();
    try {
      const category = await this.categories.create({
        name,
        normalizedName: this.normalizeName(name),
        description: input.description ?? '',
      });
      return this.toDto(category);
    } catch (error) {
      this.rethrowDuplicateName(error);
      throw error;
    }
  }

  async replace(id: string, input: CategoryInputDto): Promise<CategoryDto> {
    this.assertObjectId(id);
    const name = input.name.trim();
    try {
      const category = await this.categories
        .findByIdAndUpdate(
          id,
          {
            name,
            normalizedName: this.normalizeName(name),
            description: input.description ?? '',
          },
          { returnDocument: 'after', runValidators: true },
        )
        .exec();
      if (!category) {
        throw new NotFoundException('Category not found.');
      }
      return this.toDto(category);
    } catch (error) {
      this.rethrowDuplicateName(error);
      throw error;
    }
  }

  async delete(id: string): Promise<void> {
    this.assertObjectId(id);
    const category = await this.categories.findById(id).exec();
    if (!category) {
      throw new NotFoundException('Category not found.');
    }

    await this.products
      .updateMany({ categoryId: category._id }, { $set: { categoryId: null } })
      .exec();
    await category.deleteOne();
  }

  private assertObjectId(id: string): void {
    if (!isObjectIdOrHexString(id)) {
      throw new BadRequestException('id must be a valid MongoDB ObjectId.');
    }
  }

  private normalizeName(name: string): string {
    return name.toLowerCase();
  }

  private rethrowDuplicateName(error: unknown): void {
    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 11000
    ) {
      throw new ConflictException('A category with this name already exists.');
    }
  }

  private toDto(category: CategoryDocument): CategoryDto {
    return {
      id: category._id.toString(),
      name: category.name,
      description: category.description,
      createdAt: category.createdAt,
      updatedAt: category.updatedAt,
    };
  }
}
