import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { isObjectIdOrHexString, Model, Types } from 'mongoose';
import { Category } from '../categories/category.schema.js';
import { ProductDto, ProductInputDto } from './product.dto.js';
import { Product, ProductDocument } from './product.schema.js';

@Injectable()
export class ProductsService {
  constructor(
    @InjectModel(Product.name) private readonly products: Model<Product>,
    @InjectModel(Category.name) private readonly categories: Model<Category>,
  ) {}

  async findAll(): Promise<ProductDto[]> {
    const products = await this.products.find().sort({ name: 1 }).exec();
    return products.map((product) => this.toDto(product));
  }

  async findOne(id: string): Promise<ProductDto> {
    this.assertObjectId(id);
    const product = await this.products.findById(id).exec();
    if (!product) {
      throw new NotFoundException('Product not found.');
    }
    return this.toDto(product);
  }

  async create(input: ProductInputDto): Promise<ProductDto> {
    const categoryId = await this.getCategoryId(input.categoryId);
    const product = await this.products.create({
      name: input.name.trim(),
      description: input.description ?? '',
      price: input.price,
      categoryId,
    });
    return this.toDto(product);
  }

  async replace(id: string, input: ProductInputDto): Promise<ProductDto> {
    this.assertObjectId(id);
    const categoryId = await this.getCategoryId(input.categoryId);
    const product = await this.products
      .findByIdAndUpdate(
        id,
        {
          name: input.name.trim(),
          description: input.description ?? '',
          price: input.price,
          categoryId,
        },
        { returnDocument: 'after', runValidators: true },
      )
      .exec();
    if (!product) {
      throw new NotFoundException('Product not found.');
    }
    return this.toDto(product);
  }

  async delete(id: string): Promise<void> {
    this.assertObjectId(id);
    const product = await this.products.findByIdAndDelete(id).exec();
    if (!product) {
      throw new NotFoundException('Product not found.');
    }
  }

  private async getCategoryId(
    categoryId: string | null | undefined,
  ): Promise<Types.ObjectId | null> {
    if (categoryId == null) {
      return null;
    }
    const category = await this.categories.exists({ _id: categoryId }).exec();
    if (!category) {
      throw new NotFoundException('Category not found.');
    }
    return new Types.ObjectId(categoryId);
  }

  private assertObjectId(id: string): void {
    if (!isObjectIdOrHexString(id)) {
      throw new BadRequestException('id must be a valid MongoDB ObjectId.');
    }
  }

  private toDto(product: ProductDocument): ProductDto {
    return {
      id: product._id.toString(),
      name: product.name,
      description: product.description,
      price: product.price,
      categoryId: product.categoryId?.toString() ?? null,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
    };
  }
}
