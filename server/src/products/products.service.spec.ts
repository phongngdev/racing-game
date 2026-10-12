import { BadRequestException, NotFoundException } from '@nestjs/common';
import type { Model } from 'mongoose';
import { Category } from '../categories/category.schema.js';
import { ProductInputDto } from './product.dto.js';
import { Product } from './product.schema.js';
import { ProductsService } from './products.service.js';

describe('ProductsService', () => {
  const id = '66c1a10d6b9a5e9a6a1c0123';
  const savedProduct = {
    _id: { toString: () => id },
    name: 'ESC',
    description: '',
    price: 25,
    categoryId: null,
    createdAt: new Date('2026-10-10T00:00:00.000Z'),
    updatedAt: new Date('2026-10-10T00:00:00.000Z'),
  };
  const products = {
    find: vi.fn(),
    findById: vi.fn(),
    create: vi.fn(),
    findByIdAndUpdate: vi.fn(),
    findByIdAndDelete: vi.fn(),
  };
  const categories = { exists: vi.fn() };
  const service = new ProductsService(
    products as unknown as Model<Product>,
    categories as unknown as Model<Category>,
  );

  beforeEach(() => vi.clearAllMocks());

  it('creates an unlinked product and returns only public fields', async () => {
    products.create.mockResolvedValue(savedProduct);
    const input = { name: ' ESC ', price: 25 } as ProductInputDto;

    await expect(service.create(input)).resolves.toMatchObject({
      id,
      name: 'ESC',
      description: '',
      price: 25,
      categoryId: null,
    });
    expect(products.create).toHaveBeenCalledWith({
      name: 'ESC',
      description: '',
      price: 25,
      categoryId: null,
    });
  });

  it('rejects a category that does not exist', async () => {
    categories.exists.mockReturnValue({
      exec: vi.fn().mockResolvedValue(null),
    });
    await expect(
      service.create({
        name: 'ESC',
        price: 25,
        categoryId: id,
      } as ProductInputDto),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(products.create).not.toHaveBeenCalled();
  });

  it('returns 400 for an invalid ObjectId before querying MongoDB', async () => {
    await expect(service.findOne('bad-id')).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(products.findById).not.toHaveBeenCalled();
  });

  it('returns 404 when a valid product id does not exist', async () => {
    products.findById.mockReturnValue({
      exec: vi.fn().mockResolvedValue(null),
    });
    await expect(service.findOne(id)).rejects.toBeInstanceOf(NotFoundException);
  });
});
